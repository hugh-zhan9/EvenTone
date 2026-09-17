import AudioDSP
import CoreAudio
import Foundation
import OSLog

@available(macOS 14.2, *)
final class AudioRouter {
    private let log = Logger(subsystem: "local.eventone.app", category: "AudioRouting")
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var processor: OpaquePointer?
    private(set) var isRunning = false

    var meters: ETMeters { et_meters(processor) }

    func start(device: OutputDevice, automatic: Bool, volume: Float, trim: Float) throws {
        log.info("Starting audio route")
        try stop()
        do {
            guard device.streamCount == 1, (1...2).contains(device.channels) else {
                throw AudioFailure(message: "MVP 暂只支持单音频流的单声道或立体声输出，请切换耳机或内建扬声器。")
            }
            let own = try Hardware.ownProcess()
            let description = CATapDescription(excludingProcesses: [own], deviceUID: device.uid, stream: 0)
            description.name = "EvenTone · 本地响度处理"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try checked(AudioHardwareCreateProcessTap(description, &tap), "创建系统音频通路")
            log.info("Created process tap")

            let tapFormat = try Hardware.value(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            try validate(tapFormat, channels: device.channels, rate: device.sampleRate)
            let tapUID = try Hardware.string(tap, kAudioTapPropertyUID)
            let specification: [String: Any] = [
                kAudioAggregateDeviceNameKey: "EvenTone Processing",
                kAudioAggregateDeviceUIDKey: "local.eventone.route.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: device.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try checked(AudioHardwareCreateAggregateDevice(specification as CFDictionary, &aggregate), "建立处理输出")
            log.info("Created aggregate device")

            let inputs = try Hardware.objects(aggregate, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            let outputs = try Hardware.objects(aggregate, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            let physicalInputs = try Hardware.objects(device.id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            // Aggregate order is subdevice streams followed by tap streams. Reject unfamiliar layouts.
            guard inputs.count == physicalInputs.count + 1, let input = inputs.last, outputs.count == 1,
                  let output = outputs.first else {
                throw AudioFailure(message: "设备的音频流布局不受当前 MVP 支持。")
            }
            try validate(Hardware.format(input), channels: device.channels, rate: device.sampleRate)
            try validate(Hardware.format(output), channels: device.channels, rate: device.sampleRate)
            let startChannel = try Hardware.value(input, kAudioStreamPropertyStartingChannel, initial: UInt32(0))
            guard startChannel > 0 else { throw AudioFailure(message: "音频输入通道地址无效。") }
            guard let dsp = et_create(device.sampleRate, device.channels, startChannel - 1) else {
                throw AudioFailure(message: "无法初始化音频处理器，或采样率不受支持。")
            }
            processor = dsp
            et_configure(dsp, automatic, volume, trim)
            try checked(et_install_callback(aggregate, dsp, &ioProc), "建立实时音频回调")
            log.info("Installed IO callback")
            guard let ioProc else { throw AudioFailure(message: "未能创建实时音频回调。") }
            try checked(et_enable_tap_input(aggregate, ioProc, UInt32(inputs.count), UInt32(inputs.count - 1)), "隔离系统音频输入")
            log.info("Configured tap-only input")
            try checked(AudioDeviceStart(aggregate, ioProc), "启动音频处理")
            log.info("AudioDeviceStart returned success; waiting for callbacks")
            isRunning = true
        } catch {
            do { try stop() } catch let cleanup {
                throw AudioFailure(message: "\(error.localizedDescription)\n\(cleanup.localizedDescription)")
            }
            throw error
        }
    }

    func configure(automatic: Bool, volume: Float, trim: Float) {
        et_configure(processor, automatic, volume, trim)
    }

    func stop() throws {
        // Stop the reader before removing the tap: mutedWhenTapped releases the original path.
        var failures: [String] = []
        if let ioProc, aggregate != 0 {
            log.info("Stopping audio IO")
            let stopped = AudioDeviceStop(aggregate, ioProc)
            log.info("AudioDeviceStop returned \(stopped)")
            let destroyed = AudioDeviceDestroyIOProcID(aggregate, ioProc)
            log.info("AudioDeviceDestroyIOProcID returned \(destroyed)")
            if destroyed == noErr { self.ioProc = nil }
            else { failures.append("回调释放 \(destroyed)，停止 \(stopped)") }
        }
        if aggregate != 0 {
            let result = AudioHardwareDestroyAggregateDevice(aggregate)
            if result == noErr { aggregate = 0; ioProc = nil; failures.removeAll() }
            else { failures.append("输出通路释放 \(result)") }
        }
        // A failed HAL teardown may leave the callback alive. Retain its memory and handle
        // until a confirmed destroy, or process exit; never free memory still owned by HAL.
        if ioProc == nil {
            if let processor { et_destroy(processor) }
            processor = nil
        }
        if tap != 0 {
            let result = AudioHardwareDestroyProcessTap(tap)
            if result == noErr { tap = 0 }
            else { failures.append("音频 tap 释放 \(result)") }
        }
        isRunning = ioProc != nil
        guard failures.isEmpty else {
            throw AudioFailure(message: "音频资源未完整释放（\(failures.joined(separator: "；"))）。请退出 EvenTone，让系统回收音频通路。")
        }
    }

    private func validate(_ format: AudioStreamBasicDescription, channels: UInt32, rate: Double) throws {
        let floatPCM = format.mFormatID == kAudioFormatLinearPCM &&
            format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32 &&
            format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
        let sampleChannels: UInt32 = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 ? channels : 1
        guard floatPCM, format.mChannelsPerFrame == channels, abs(format.mSampleRate - rate) < 1,
              format.mBytesPerFrame == 4 * sampleChannels, format.mFramesPerPacket == 1 else {
            throw AudioFailure(message: "设备音频格式不兼容。MVP 需要 32 位浮点单声道或立体声音频。")
        }
    }

    deinit { try? stop() }
}

/// HAL calls can wait on the audio daemon (including permission prompts). Keep those
/// waits off the UI thread, and serialize every pointer read with creation/destruction.
@available(macOS 14.2, *)
// Unchecked Sendable is confined to this queue-owning wrapper: no mutable HAL state
// escapes, and all router / monitor operations are submitted to the same serial queue.
final class AudioWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.eventone.audio-control", qos: .userInitiated)
    private let router = AudioRouter()
    private let monitor = DeviceMonitor()
    private let referencePlayer = ReferencePlayer()
    private var selection: OutputSelection?

    func currentDevice() async throws -> OutputDevice {
        try await perform { _ in try OutputDevice.current() }
    }

    func availableDevices() async throws -> [OutputDevice] {
        try await perform { _ in try OutputDevice.available() }
    }

    func selectOutput(uid: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    let backend = try HALOutputSwitchBackend(uid: uid, queue: queue)
                    let request = OutputSelection(targetUID: uid, backend: backend)
                    selection = request
                    request.start { [self] result in
                        selection = nil
                        continuation.resume(with: result)
                    }
                    queue.asyncAfter(deadline: .now() + 5) { [weak request] in request?.timeout() }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func watch(device: OutputDevice?, onChange: @escaping () -> Void) async throws {
        try await perform { [self] _ in try monitor.watch(device: device, onChange: onChange) }
    }

    func start(device: OutputDevice, automatic: Bool, volume: Float, trim: Float) async throws {
        try await perform { router in
            try router.start(device: device, automatic: automatic, volume: volume, trim: trim)
        }
    }

    func stop() async throws {
        try await perform { router in try router.stop() }
    }

    func playReference(uid: String, volume: Double, trim: Double) async throws {
        // The process tap excludes this app, so the reference is never processed twice.
        try await perform { [self] _ in
            try referencePlayer.play(uid: uid, volume: volume, trim: trim)
        }
    }

    func stopReference() async throws { try await perform { [self] _ in referencePlayer.stop() } }
    func referenceIsPlaying() async throws -> Bool { try await perform { [self] _ in try referencePlayer.isPlaying() } }
    func meters() async throws -> ETMeters { try await perform { $0.meters } }

    func configure(automatic: Bool, volume: Float, trim: Float) {
        queue.async { [self] in router.configure(automatic: automatic, volume: volume, trim: trim) }
    }

    func stopForExit() {
        // Best effort only: termination must remain available even if HAL is stalled.
        // The OS also reclaims this process's private audio objects on process exit.
        queue.async { [self] in
            referencePlayer.stop()
            try? router.stop()
            monitor.stop()
        }
    }

    private func perform<T>(_ operation: @escaping (AudioRouter) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do { continuation.resume(returning: try operation(router)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
