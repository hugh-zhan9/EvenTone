import CoreAudio
import Foundation

struct AudioFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func checked(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw AudioFailure(message: "\(operation)失败（Core Audio \(status)）。若尚未授权，请检查系统音频录制权限。")
    }
}

enum Hardware {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        var property = address(selector, scope)
        try withUnsafeMutablePointer(to: &result) { pointer in
            try checked(AudioObjectGetPropertyData(object, &property, 0, nil, &size, pointer), "读取音频属性")
        }
        return result
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var property = address(selector, scope)
        var size: UInt32 = 0
        try checked(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size), "读取设备列表大小")
        guard size > 0 else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try result.withUnsafeMutableBytes { data in
            try checked(AudioObjectGetPropertyData(object, &property, 0, nil, &size, data.baseAddress!), "读取设备列表")
        }
        return result
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var property = address(selector)
        var result: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        try withUnsafeMutablePointer(to: &result) { pointer in
            try checked(AudioObjectGetPropertyData(object, &property, 0, nil, &size, pointer), "读取设备名称")
        }
        return result as String
    }

    static func format(_ stream: AudioObjectID) throws -> AudioStreamBasicDescription {
        try value(stream, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
    }

    static func ownProcess() throws -> AudioObjectID {
        var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var result: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try checked(AudioObjectGetPropertyData(system, &property, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &result), "识别自身音频进程")
        guard result != 0 else { throw AudioFailure(message: "尚不能识别自身音频进程，未启用音频处理。请重新打开应用。") }
        return result
    }
}

struct OutputDevice: Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let sampleRate: Double
    let channels: UInt32
    let streamCount: Int
    let formatID: AudioFormatID
    let formatFlags: AudioFormatFlags
    let bytesPerFrame: UInt32
    let bitsPerChannel: UInt32
    let framesPerPacket: UInt32

    static func current() throws -> OutputDevice {
        let id = try Hardware.value(Hardware.system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
        return try read(id: id)
    }

    static func read(id: AudioObjectID) throws -> OutputDevice {
        guard id != 0 else { throw AudioFailure(message: "没有可用的音频输出设备。") }
        let alive = try Hardware.value(id, kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0))
        guard alive != 0 else { throw AudioFailure(message: "当前输出设备已断开。") }
        let streams = try Hardware.objects(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        guard let first = streams.first else { throw AudioFailure(message: "当前设备没有输出音频流。") }
        let format = try Hardware.format(first)
        return OutputDevice(id: id, uid: try Hardware.string(id, kAudioDevicePropertyDeviceUID),
                            name: try Hardware.string(id, kAudioObjectPropertyName),
                            sampleRate: format.mSampleRate, channels: format.mChannelsPerFrame, streamCount: streams.count,
                            formatID: format.mFormatID, formatFlags: format.mFormatFlags,
                            bytesPerFrame: format.mBytesPerFrame, bitsPerChannel: format.mBitsPerChannel,
                            framesPerPacket: format.mFramesPerPacket)
    }

    static func available() throws -> [OutputDevice] {
        let ids = try Hardware.objects(Hardware.system, kAudioHardwarePropertyDevices)
        // Hot-unplug may invalidate an individual ID while enumerating. Such entries,
        // input-only devices, and non-default-capable devices are not selectable.
        return ids.compactMap { id in
            guard let candidate = try? read(id: id),
                  !candidate.uid.hasPrefix("local.eventone.route."),
                  let selectable = try? Hardware.value(id, kAudioDevicePropertyDeviceCanBeDefaultDevice,
                      initial: UInt32(0), scope: kAudioObjectPropertyScopeOutput), selectable != 0 else { return nil }
            return candidate
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.uid < $1.uid : order == .orderedAscending
        }
    }
}

/// Registration/removal runs on AudioWorker; event delivery alone uses the main queue.
final class DeviceMonitor {
    private var registrations: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func watch(device: OutputDevice?, onChange: @escaping () -> Void) throws {
        stop()
        try add(Hardware.system, Hardware.address(kAudioHardwarePropertyDefaultOutputDevice), onChange)
        try add(Hardware.system, Hardware.address(kAudioHardwarePropertyDevices), onChange)
        if let device {
            try add(device.id, Hardware.address(kAudioDevicePropertyNominalSampleRate), onChange)
            try add(device.id, Hardware.address(kAudioDevicePropertyDeviceIsAlive), onChange)
            try add(device.id, Hardware.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput), onChange)
            for stream in try Hardware.objects(device.id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) {
                try add(stream, Hardware.address(kAudioStreamPropertyVirtualFormat), onChange)
            }
        }
    }

    private func add(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ changed: @escaping () -> Void) throws {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        try checked(AudioObjectAddPropertyListenerBlock(object, &address, .main, block), "监听设备变化")
        registrations.append((object, address, block))
    }

    func stop() {
        for (object, var address, block) in registrations {
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        registrations.removeAll()
    }

    deinit { stop() }
}

/// Constructed, observed, and disposed exclusively on AudioWorker's serial queue.
final class HALOutputSwitchBackend: OutputSwitchBackend {
    private let target: OutputDevice
    private let queue: DispatchQueue
    private var listener: AudioObjectPropertyListenerBlock?

    init(uid: String, queue: DispatchQueue) throws {
        guard let target = try OutputDevice.available().first(where: { $0.uid == uid }) else {
            throw AudioFailure(message: "所选输出设备已断开或不可用，请重新选择。")
        }
        self.target = target
        self.queue = queue
    }

    func currentUID() throws -> String {
        let id = try Hardware.value(Hardware.system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
        return id == 0 ? "" : try Hardware.string(id, kAudioDevicePropertyDeviceUID)
    }

    func request() throws {
        guard try OutputDevice.read(id: target.id).uid == target.uid else {
            throw AudioFailure(message: "设备连接已变化，请重新选择输出设备。")
        }
        var property = Hardware.address(kAudioHardwarePropertyDefaultOutputDevice)
        var settable: DarwinBoolean = false
        try checked(AudioObjectIsPropertySettable(Hardware.system, &property, &settable), "检查设备切换权限")
        guard settable.boolValue else { throw AudioFailure(message: "系统当前不允许切换默认输出设备。") }
        var id = target.id
        try checked(AudioObjectSetPropertyData(Hardware.system, &property, 0, nil,
                    UInt32(MemoryLayout<AudioObjectID>.size), &id), "切换输出设备")
    }

    func observe(_ changed: @escaping () -> Void) throws {
        var property = Hardware.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        try checked(AudioObjectAddPropertyListenerBlock(Hardware.system, &property, queue, block), "等待设备切换")
        listener = block
    }

    func stopObserving() throws {
        guard let listener else { return }
        var property = Hardware.address(kAudioHardwarePropertyDefaultOutputDevice)
        try checked(AudioObjectRemovePropertyListenerBlock(Hardware.system, &property, queue, listener), "结束设备切换监听")
        self.listener = nil
    }
}
