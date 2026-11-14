import AudioDSP
import CoreAudio
import Foundation
import OSLog

@available(macOS 14.2, *)
final class AudioRouter {
    private let log = Logger(subsystem: "local.eventone.app", category: "AudioRouting")
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var muteTap: AudioObjectID = 0
    private var callMuteTap: AudioObjectID = 0
    private var passthroughDeviceUID: String?
    private var muteAggregate: AudioObjectID = 0
    private var muteIOProc: AudioDeviceIOProcID?
    private let muteRouting = ProcessMuteRoutingState()
    private var routeDevice: OutputDevice?
    private var ownProcess: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var processor: OpaquePointer?
    private(set) var isRunning = false
    private var passthrough = false
    var isActive: Bool { isRunning || passthrough }

    var meters: ETMeters { et_meters(processor) }

    func start(device: OutputDevice, automatic: Bool, volume: Float, trim: Float, muted: Set<UInt32> = []) throws {
        log.info("Starting audio route")
        try stop()
        do {
            guard device.streamCount == 1, (1...2).contains(device.channels) else {
                throw AudioFailure(message: "MVP 暂只支持单音频流的单声道或立体声输出，请切换耳机或内建扬声器。")
            }
            let own = try Hardware.ownProcess()
            ownProcess = own
            routeDevice = device
            try updateMuteTap(muted)
            let description = CATapDescription(excludingProcesses: Array(muted.union([own])).sorted(), deviceUID: device.uid, stream: 0)
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
            muteRouting.reset(applied: muted)
        } catch {
            do { try stop() } catch let cleanup {
                throw AudioFailure(message: "\(error.localizedDescription)\n\(cleanup.localizedDescription)")
            }
            throw error
        }
    }

    func startPassthrough(muted: Set<UInt32>, deviceUID: String? = nil) throws {
        try stop()
        passthroughDeviceUID = deviceUID
        do {
            if !muted.isEmpty { ownProcess = try Hardware.ownProcess() }
            let target = muted.subtracting([ownProcess])
            try updateMuteTap(target)
            passthrough = true
            muteRouting.reset(applied: target)
        } catch {
            do { try stop() } catch let cleanup {
                throw AudioFailure(message: "\(error.localizedDescription)\n\(cleanup.localizedDescription)")
            }
            throw error
        }
    }

    func setMutedProcesses(_ processes: Set<UInt32>) throws {
        try muteRouting.checkHealth()
        guard isActive else { return }
        if !processes.isEmpty && ownProcess == 0 { ownProcess = try Hardware.ownProcess() }
        let target = processes.subtracting([ownProcess])
        if passthrough {
            try muteRouting.update(target, suppress: { [self] in try updateMuteTap($0) },
                                   exclude: { _ in }, cleanup: { [self] in try stop() })
            return
        }
        guard let device = routeDevice else { return }
        try muteRouting.update(target, suppress: { [self] in try updateMuteTap($0) }, exclude: { [self] excluded in
            let description = CATapDescription(excludingProcesses: Array(excluded.union([ownProcess])).sorted(),
                                               deviceUID: device.uid, stream: 0)
            description.name = "EvenTone · 本地响度处理"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try setDescription(description, on: tap)
        }, cleanup: { [self] in try stop() })
    }

    func checkMuteHealth() throws { try muteRouting.checkHealth() }

    private func setDescription(_ description: CATapDescription, on object: AudioObjectID) throws {
        guard let uuid = UUID(uuidString: try Hardware.string(object, kAudioTapPropertyUID)) else {
            throw AudioFailure(message: "音频通路标识无效。")
        }
        description.uuid = uuid
        var description = description
        var property = Hardware.address(kAudioTapPropertyDescription)
        try withUnsafePointer(to: &description) { pointer in
            try checked(AudioObjectSetPropertyData(object, &property, 0, nil,
                        UInt32(MemoryLayout<CATapDescription>.size), pointer), "更新应用音频通路")
        }
    }

    private func updateMuteTap(_ processes: Set<UInt32>) throws {
        if processes.isEmpty {
            try stopMuteReader()
            if muteTap != 0 {
                try checked(AudioHardwareDestroyProcessTap(muteTap), "解除应用静音")
                muteTap = 0
            }
            if callMuteTap != 0 {
                try checked(AudioHardwareDestroyProcessTap(callMuteTap), "解除通话应用静音")
                callMuteTap = 0
            }
        } else {
            let description = Hardware.applicationMuteDescription(processes)
            if muteTap == 0 {
                try checked(AudioHardwareCreateProcessTap(description, &muteTap), "静音应用")
                let uid = try Hardware.string(muteTap, kAudioTapPropertyUID)
                var taps: [[String: Any]] = [[kAudioSubTapUIDKey: uid]]
                if let passthroughDeviceUID {
                    let callDescription = Hardware.applicationMuteDescription(processes, deviceUID: passthroughDeviceUID)
                    try checked(AudioHardwareCreateProcessTap(callDescription, &callMuteTap), "建立通话设备静音")
                    let callUID = try Hardware.string(callMuteTap, kAudioTapPropertyUID)
                    taps.append([kAudioSubTapUIDKey: callUID])
                }
                let specification: [String: Any] = [
                    kAudioAggregateDeviceNameKey: "EvenTone Muted Audio",
                    kAudioAggregateDeviceUIDKey: "local.eventone.mute.\(UUID().uuidString)",
                    kAudioAggregateDeviceIsPrivateKey: true,
                    kAudioAggregateDeviceTapListKey: taps,
                    kAudioAggregateDeviceTapAutoStartKey: true
                ]
                try checked(AudioHardwareCreateAggregateDevice(specification as CFDictionary, &muteAggregate), "建立应用静音读取通路")
                // Input-only aggregate: no microphone, hardware output, recording or retained samples.
                try checked(AudioDeviceCreateIOProcID(muteAggregate, { _, _, _, _, _, _, _ in noErr },
                                                     nil, &muteIOProc), "建立应用静音回调")
                guard let muteIOProc else { throw AudioFailure(message: "未能创建应用静音回调。") }
                try checked(AudioDeviceStart(muteAggregate, muteIOProc), "启动应用静音通路")
            } else {
                try setDescription(description, on: muteTap)
                if let passthroughDeviceUID {
                    try setDescription(Hardware.applicationMuteDescription(processes, deviceUID: passthroughDeviceUID), on: callMuteTap)
                }
            }
        }
    }

    private func stopMuteReader() throws {
        if let muteIOProc, muteAggregate != 0 {
            _ = AudioDeviceStop(muteAggregate, muteIOProc)
            let destroyed = AudioDeviceDestroyIOProcID(muteAggregate, muteIOProc)
            if destroyed == noErr { self.muteIOProc = nil }
            // Destroying the aggregate below also releases a callback if explicit destroy failed.
        }
        if muteAggregate != 0 {
            try checked(AudioHardwareDestroyAggregateDevice(muteAggregate), "释放应用静音读取通路")
            muteAggregate = 0
            muteIOProc = nil
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
        do { try stopMuteReader() }
        catch { failures.append(error.localizedDescription) }
        if muteTap != 0 && muteAggregate == 0 {
            let result = AudioHardwareDestroyProcessTap(muteTap)
            if result == noErr { muteTap = 0 }
            else { failures.append("应用静音释放 \(result)") }
        }
        if callMuteTap != 0 && muteAggregate == 0 {
            let result = AudioHardwareDestroyProcessTap(callMuteTap)
            if result == noErr { callMuteTap = 0 }
            else { failures.append("通话静音释放 \(result)") }
        }
        if tap == 0 && muteTap == 0 && callMuteTap == 0 {
            routeDevice = nil
            passthroughDeviceUID = nil
        }
        isRunning = ioProc != nil
        passthrough = false
        guard failures.isEmpty else {
            throw AudioFailure(message: "音频资源未完整释放（\(failures.joined(separator: "；"))）。请退出 EvenTone，让系统回收音频通路。")
        }
        muteRouting.reset()
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
    private var applicationMutes = ApplicationMuteState()
    private var callMutesBypassed = false

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

    func start(device: OutputDevice, automatic: Bool, volume: Float, trim: Float, experimentalCallMuting: Bool = false) async throws -> Bool {
        try await perform { [self] router in
            let processing = try ProcessingStartup.run(callMode: device.isBluetoothCallMode, start: {
                let applications = try AudioApplications.read()
                try router.start(device: device, automatic: automatic, volume: volume, trim: trim,
                                 muted: applicationMutes.processIDs(in: applications))
            }, stop: {
                try router.stop()
            }, currentCallMode: {
                try OutputDevice.current().isBluetoothCallMode
            })
            callMutesBypassed = !processing && !experimentalCallMuting
            if !processing {
                // Authorization can span a device switch. Never bind the extra tap
                // to the snapshot that failed to start; AppModel reconciles mode exits.
                let callUID = callMutesBypassed ? nil : try ProcessingStartup.currentCallDeviceUID(read: OutputDevice.current)
                let applications = callUID == nil || applicationMutes.selected.isEmpty ? [] : try AudioApplications.read()
                try router.startPassthrough(muted: applicationMutes.processIDs(in: applications), deviceUID: callUID)
            }
            return processing
        }
    }

    func applications() async throws -> [AudioApplication] {
        try await perform { [self] router in
            try router.checkMuteHealth()
            guard router.isActive && !callMutesBypassed else { return [] }
            let applications = try AudioApplications.read()
            try router.setMutedProcesses(applicationMutes.processIDs(in: applications))
            return applicationMutes.rows(applications)
        }
    }

    func setApplicationMuted(id: String, muted: Bool) async throws -> [AudioApplication] {
        try await perform { [self] router in
            guard router.isActive && !callMutesBypassed else {
                throw AudioFailure(message: "当前未启用应用静音控制。")
            }
            let applications = try AudioApplications.read()
            guard let application = applicationMutes.rows(applications).first(where: { $0.id == id }) else {
                throw AudioFailure(message: "该应用已停止音频输出，请刷新后重试。")
            }
            try applicationMutes.set(application, muted: muted, applications: applications) {
                try router.setMutedProcesses($0)
            }
            return applicationMutes.rows(applications)
        }
    }

    func stop(clearApplicationMutes: Bool = false) async throws {
        try await perform { [self] router in
            if clearApplicationMutes { applicationMutes.clear() }
            callMutesBypassed = false
            try router.stop()
        }
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
