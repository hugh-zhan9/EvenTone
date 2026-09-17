import Foundation

enum ReferenceSignal {
    static let sampleRate = 48_000
    static let seconds = 6

    // Same deterministic noise on every audition, independent of the device's rate.
    // The WAV has 12 dB of headroom gain baked in; the player only attenuates it.
    static func samples() -> [Float] {
        let count = sampleRate * seconds
        var seed: UInt32 = 0x45564E54
        var low: Float = 0
        var signal = [Float](repeating: 0, count: count)
        var energy: Double = 0
        for i in 0..<count {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let white = Float(Double(seed) / Double(UInt32.max) * 2 - 1)
            low = 0.96 * low + 0.04 * white
            let value = low + 0.12 * white
            signal[i] = value
            energy += Double(value * value)
        }
        let normalization = Float(0.04 / sqrt(energy / Double(count)))
        let fade = sampleRate / 10
        let maximumGain = Float(pow(10.0, 12.0 / 20))
        for i in signal.indices {
            let envelope = Float(min(fade, min(i, count - 1 - i))) / Float(fade)
            signal[i] = min(0.2, max(-0.2, signal[i] * normalization)) * maximumGain * envelope
        }
        return signal
    }

    static func wav() -> Data {
        let signal = samples()
        let bytes = signal.count * 4 // two identical PCM16 channels
        var result = Data(capacity: 44 + bytes)
        func text(_ value: String) { result.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            result.append(UInt8(truncatingIfNeeded: value))
            result.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func u32(_ value: UInt32) { u16(UInt16(truncatingIfNeeded: value)); u16(UInt16(value >> 16)) }
        text("RIFF"); u32(UInt32(36 + bytes)); text("WAVEfmt "); u32(16)
        u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(16)
        text("data"); u32(UInt32(bytes))
        for value in signal {
            let pcm = UInt16(bitPattern: Int16((value * 32767).rounded()))
            u16(pcm); u16(pcm)
        }
        return result
    }

    static func playbackVolume(volume: Double, trim: Double) -> Float {
        guard volume.isFinite, trim.isFinite else { return 0 }
        return Float(min(1, max(0, volume)) * pow(10, (min(12, max(-12, trim)) - 12) / 20))
    }
}
