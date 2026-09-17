import AppKit
import CoreAudio
import SwiftUI

@available(macOS 14.2, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@available(macOS 14.2, *)
struct EvenToneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("EvenTone · 匀声", id: "control") {
            ControlView(model: model).onAppear { delegate.model = model }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

        MenuBarExtra {
            ControlView(model: model).onAppear { delegate.model = model }
        } label: {
            Image(systemName: model.enabled ? "waveform.circle.fill" : "waveform.circle")
        }.menuBarExtraStyle(.window)
    }
}

if CommandLine.arguments.contains("--diagnose") {
    do {
        let device = try OutputDevice.current()
        print("EvenTone audio diagnostics (read-only)")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Default output: \(device.name)")
        print("Format: \(device.sampleRate) Hz, \(device.channels) channels, \(device.streamCount) stream(s)")
        print("Device ID: \(device.id)")
        let outputs = try OutputDevice.available()
        print("Selectable outputs: \(outputs.count)")
        for output in outputs { print("  \(output.id == device.id ? "*" : "-") \(output.name) (\(output.sampleRate) Hz)") }
        print("No tap created; no audio captured; no system settings changed.")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if #available(macOS 14.2, *) {
    EvenToneApp.main()
} else {
    fputs("EvenTone requires macOS 14.2 or later.\n", stderr)
    exit(1)
}
