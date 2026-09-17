import AudioDSP
import CoreAudio
import Foundation

final class DSPTests {
    private let rate = 48_000.0

    private func processor(channels: UInt32 = 2, automatic: Bool = true, volume: Float = 1, trim: Float = 0) throws -> OpaquePointer {
        let p = try unwrap(et_create(rate, channels, 0))
        et_configure(p, automatic, volume, trim)
        return p
    }

    @discardableResult
    private func tone(_ p: OpaquePointer, amplitude: Float, seconds: Double, channels: Int = 2) -> [Float] {
        let frames = 480
        let input = (0..<frames).flatMap { frame in
            Array(repeating: amplitude * sin(2 * .pi * Float(frame) / 48), count: channels)
        }
        var output = [Float](repeating: 0, count: input.count)
        for _ in 0..<Int(seconds * rate / Double(frames)) {
            et_process(p, input, &output, UInt32(frames))
        }
        return output
    }

    func testQuietAndLoudVideosConverge() throws {
        let quiet = try processor(), loud = try processor()
        defer { et_destroy(quiet); et_destroy(loud) }
        tone(quiet, amplitude: 0.03, seconds: 8)
        tone(loud, amplitude: 0.5, seconds: 8)
        let a = et_meters(quiet), b = et_meters(loud)
        expectGreater(a.automaticGainDB, 10)
        expectLess(b.automaticGainDB, -10)
        expectEqual(a.outputDB, b.outputDB, accuracy: 0.4)
        expectEqual(a.outputDB, -22, accuracy: 0.4)
    }

    func testQuietToLoudTransitionStaysUnderCeilingAndSettles() throws {
        let p = try processor()
        defer { et_destroy(p) }
        tone(p, amplitude: 0.03, seconds: 8)
        let input = [Float](repeating: 1, count: 1920)
        var output = input
        et_process(p, input, &output, 960)
        expectAtMost(output.map(abs).max()!, 0.8912511)
        expectGreater(et_meters(p).reductionDB, 1)
        tone(p, amplitude: 0.5, seconds: 5)
        expectEqual(et_meters(p).outputDB, -22, accuracy: 0.5)
    }

    func testSilenceAndVeryLowNoiseDoNotAccumulateBoost() throws {
        let p = try processor()
        defer { et_destroy(p) }
        let silence = tone(p, amplitude: 0, seconds: 3)
        expectTrue(silence.allSatisfy { $0 == 0 })
        expectEqual(et_meters(p).automaticGainDB, 0, accuracy: 0.001)
        tone(p, amplitude: 0.0001, seconds: 3)
        expectEqual(et_meters(p).automaticGainDB, 0, accuracy: 0.001)
        tone(p, amplitude: 0.04, seconds: 1)
        let before = et_meters(p).automaticGainDB
        tone(p, amplitude: 0, seconds: 3)
        expectAtMost(et_meters(p).automaticGainDB, before + 0.07)
    }

    func testManualCalibrationAndVolumeWhenAutomaticDisabled() throws {
        let p = try processor(automatic: false, volume: 0.5, trim: 6)
        defer { et_destroy(p) }
        tone(p, amplitude: 0.1, seconds: 2)
        let meter = et_meters(p)
        expectEqual(meter.automaticGainDB, 0, accuracy: 0.001)
        expectEqual(meter.outputDB - meter.inputDB, -0.0206, accuracy: 0.05)
    }

    func testLimiterPreservesStereoRatio() throws {
        let p = try processor(automatic: false, trim: 12)
        defer { et_destroy(p) }
        let input = Array(repeating: [Float(0.8), Float(0.2)], count: 480).flatMap { $0 }
        var output = input
        for _ in 0..<100 { et_process(p, input, &output, 480) }
        for i in stride(from: 0, to: output.count, by: 2) {
            expectEqual(output[i], output[i + 1] * 4, accuracy: 0.00001)
            expectAtMost(abs(output[i]), 0.8912511)
        }
    }

    func testInvalidNumbersEmptySingleFrameAndMono() throws {
        expectNil(et_create(0, 2, 0))
        expectNil(et_create(.nan, 2, 0))
        expectNil(et_create(rate, 8, 0))
        let p = try processor(channels: 1, automatic: false)
        defer { et_destroy(p) }
        et_configure(p, false, .nan, .infinity)
        et_process(p, nil, nil, 0)
        let input: [Float] = [.nan, .infinity, -.infinity, 0.5]
        var output = [Float](repeating: 9, count: 4)
        et_process(p, input, &output, 4)
        expectTrue(output.allSatisfy(\.isFinite))
        expectEqual(Array(output.prefix(3)), [0, 0, 0])
        var one: Float = 0
        var result: Float = 1
        et_process(p, &one, &result, 1)
        expectEqual(result, 0)
    }

    func testGainLimitAndZeroVolume() throws {
        let p = try processor()
        defer { et_destroy(p) }
        tone(p, amplitude: 0.006, seconds: 8)
        expectAtMost(et_meters(p).automaticGainDB, 12.001)
        et_configure(p, true, 0, 0)
        let output = tone(p, amplitude: 0.5, seconds: 2)
        expectLess(output.map(abs).max()!, 0.000001)
    }

    func testIOMapsTapAfterDisabledMicrophoneAndPlanarOutput() throws {
        let p = try unwrap(et_create(rate, 2, 1))
        defer { et_destroy(p) }
        et_configure(p, false, 1, 0)
        let frames = 480
        let input = AudioBufferList.allocate(maximumBuffers: 2)
        let output = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(input.unsafeMutablePointer); free(output.unsafeMutablePointer) }
        var signal = Array(repeating: [Float(0.1), Float(0.2)], count: frames).flatMap { $0 }
        var left = [Float](repeating: 0, count: frames), right = left
        signal.withUnsafeMutableBytes { src in
            left.withUnsafeMutableBytes { l in
                right.withUnsafeMutableBytes { r in
                    input[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: nil)
                    input[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(src.count), mData: src.baseAddress)
                    output[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(l.count), mData: l.baseAddress)
                    output[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(r.count), mData: r.baseAddress)
                    for _ in 0..<100 {
                        _ = et_io_proc(0, nil, input.unsafePointer, nil, output.unsafeMutablePointer, nil, UnsafeMutableRawPointer(p))
                    }
                }
            }
        }
        expectFalse(et_meters(p).formatFault)
        expectEqual(left.last!, 0.1, accuracy: 0.0001)
        expectEqual(right.last!, 0.2, accuracy: 0.0001)
    }

    func testIORejectsMismatchedBuffersWithSilence() throws {
        let p = try processor(channels: 1)
        defer { et_destroy(p) }
        let input = AudioBufferList.allocate(maximumBuffers: 1)
        let output = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(input.unsafeMutablePointer); free(output.unsafeMutablePointer) }
        var source = [Float](repeating: 0.3, count: 8), destination = [Float](repeating: 0.7, count: 4)
        source.withUnsafeMutableBytes { src in
            destination.withUnsafeMutableBytes { dst in
                input[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(src.count), mData: src.baseAddress)
                output[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(dst.count), mData: dst.baseAddress)
                _ = et_io_proc(0, nil, input.unsafePointer, nil, output.unsafeMutablePointer, nil, UnsafeMutableRawPointer(p))
            }
        }
        expectTrue(et_meters(p).formatFault)
        expectTrue(destination.allSatisfy { $0 == 0 })
    }
}
