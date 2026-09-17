import AppKit
import AudioDSP
import Combine
import Foundation

@MainActor
@available(macOS 14.2, *)
final class AppModel: ObservableObject {
    @Published private(set) var device: OutputDevice?
    @Published private(set) var outputDevices: [OutputDevice] = []
    @Published private(set) var enabled = false {
        didSet { preferences.processingEnabled = enabled }
    }
    @Published private(set) var suspended = false
    @Published private(set) var busy = false
    @Published private(set) var receivingAudio = false
    @Published private(set) var error: String?
    @Published private(set) var meters = ETMeters(inputDB: -120, outputDB: -120, automaticGainDB: 0, reductionDB: 0, callbacks: 0, formatFault: false)
    @Published var volume: Double { didSet { preferences.volume = volume; configure() } }
    @Published var automatic: Bool { didSet { preferences.automatic = automatic; configure() } }
    @Published var trim: Double = 0 {
        didSet {
            if let device { preferences.setTrim(trim, for: device.uid) }
            configure()
        }
    }

    private let preferences: Preferences
    let loginItem = LoginItemController()
    private let worker = AudioWorker()
    private var timer: Timer?
    private var observations: [NSObjectProtocol] = []
    private var lastCallbackAt = Date.distantPast
    private var lastCallbacks: UInt32 = 0
    private var running = false
    private var refreshPending = false
    private var pollPending = false
    private var generation = 0
    private var busyMessage = "正在检测设备…"
    private var exiting = false

    var hasSignal: Bool { enabled && running && !suspended && receivingAudio && meters.inputDB > -70 }
    var status: String {
        if busy { return busyMessage }
        if error != nil { return "需要处理" }
        if suspended { return "睡眠暂停" }
        if !enabled { return "已关闭" }
        return hasSignal ? "正在处理音频" : "已启动 · 等待音频"
    }

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        volume = preferences.volume
        automatic = preferences.automatic
        enabled = preferences.processingEnabled
        refreshDevice()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.loginItem.refresh() }
        })
        observations.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                self.suspended = true
                self.refreshDevice()
            }
        })
        observations.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.suspended else { return }
                self.suspended = false
                self.refreshDevice()
            }
        })
    }

    func setEnabled(_ value: Bool) {
        guard !busy else { return }
        error = nil
        enabled = value
        runOperation(value ? "正在连接音频…" : "正在关闭…") { [self] in
            if value {
                try await syncDevice()
                try await startCurrent()
            } else {
                suspended = false
                try await stop()
            }
        }
    }

    func refreshDevice() {
        guard !exiting else { return }
        if busy { refreshPending = true; return }
        runOperation("正在更新设备…") { [self] in
            outputDevices = try await worker.availableDevices()
            try await syncDevice()
            if suspended {
                try await stop()
            } else if enabled && !running {
                try await startCurrent()
            }
        }
    }

    func selectOutput(uid: String) {
        guard !busy, device?.uid != uid else { return }
        error = nil
        runOperation("正在切换输出…") { [self] in
            try await stop()
            try await worker.selectOutput(uid: uid)
            outputDevices = try await worker.availableDevices()
            try await syncDevice()
            if enabled && !suspended { try await startCurrent() }
        }
    }

    private func syncDevice() async throws {
        let next: OutputDevice
        do { next = try await worker.currentDevice() }
        catch { device = nil; throw error }
        guard next != device else { return }
        try await stop()
        device = next
        trim = preferences.trim(for: next.uid)
        try await installMonitor()
    }

    private func installMonitor() async throws {
        try await worker.watch(device: device) { [weak self] in
            Task { @MainActor in self?.refreshDevice() }
        }
    }

    private func startCurrent() async throws {
        guard !suspended, let device else { return }
        try await worker.start(device: device, automatic: automatic, volume: Float(volume), trim: Float(trim))
        running = true
        // Apply any slider changes made while HAL was waiting for permission.
        worker.configure(automatic: automatic, volume: Float(volume), trim: Float(trim))
        receivingAudio = false
        lastCallbackAt = .distantPast
        lastCallbacks = 0
    }

    private func stop() async throws {
        try await worker.stop()
        running = false
        receivingAudio = false
        meters = try await worker.meters()
    }

    private func runOperation(_ message: String, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !exiting else { return }
        busy = true
        busyMessage = message
        generation += 1
        Task { [self] in
            do { try await operation() }
            catch {
                enabled = false
                running = false
                self.error = error.localizedDescription
                do { try await worker.stop() }
                catch { self.error = "\(self.error ?? "")\n\(error.localizedDescription)" }
                // No device or a disconnected device still needs the default-output listener.
                if device == nil { try? await installMonitor() }
            }
            busy = false
            configure()
            if refreshPending && !exiting {
                refreshPending = false
                refreshDevice()
            }
        }
    }

    private func configure() {
        // Bound the queue while a synchronous HAL call is pending; startCurrent applies
        // the latest settings once it returns.
        guard !busy else { return }
        worker.configure(automatic: automatic, volume: Float(volume), trim: Float(trim))
    }

    private func poll() {
        guard enabled && running && !suspended && !busy && !pollPending && !exiting else { return }
        pollPending = true
        let expectedGeneration = generation
        Task { [self] in
            defer { pollPending = false }
            guard let snapshot = try? await worker.meters(), expectedGeneration == generation else { return }
            meters = snapshot
            if meters.callbacks != lastCallbacks {
                lastCallbacks = meters.callbacks
                lastCallbackAt = Date()
            }
            // Idle / suspended hardware can stop calling IO without an error. Use freshness
            // only for the display, never as a reason to tear down a successfully opened route.
            receivingAudio = Date().timeIntervalSince(lastCallbackAt) < 0.5
            if meters.formatFault {
                fail("输出设备的音频缓冲格式发生变化，请确认设备后重新开启。")
            }
        }
    }

    private func fail(_ message: String) {
        error = message
        enabled = false
        runOperation("正在释放音频通路…") { [self] in try await stop() }
    }

    func shutdown() {
        exiting = true
        timer?.invalidate()
        timer = nil
        worker.stopForExit()
        observations.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observations.removeAll()
    }

    func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
