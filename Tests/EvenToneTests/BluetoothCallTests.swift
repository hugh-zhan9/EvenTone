import CoreAudio
import Foundation

final class BluetoothCallTests {
    private func device(rate: Double, transport: UInt32) -> OutputDevice {
        OutputDevice(id: 0, uid: "test-only-nonexistent", name: "Test", sampleRate: rate,
                     channels: 2, streamCount: 1, formatID: kAudioFormatLinearPCM,
                     formatFlags: kAudioFormatFlagIsFloat, bytesPerFrame: 8,
                     bitsPerChannel: 32, framesPerPacket: 1, transportType: transport)
    }

    func testOnlyClassicBluetoothCommunicationRatesBypass() {
        for rate in [8_000.0, 16_000, 24_000] {
            expectTrue(device(rate: rate, transport: kAudioDeviceTransportTypeBluetooth).isBluetoothCallMode)
            expectFalse(device(rate: rate, transport: kAudioDeviceTransportTypeBuiltIn).isBluetoothCallMode)
            expectFalse(device(rate: rate, transport: kAudioDeviceTransportTypeUSB).isBluetoothCallMode)
        }
        for rate in [0.0, -.infinity, .nan, 32_000, 44_100, 48_000, 96_000] {
            expectFalse(device(rate: rate, transport: kAudioDeviceTransportTypeBluetooth).isBluetoothCallMode)
        }
        let music = device(rate: 48_000, transport: kAudioDeviceTransportTypeBluetooth)
        let call = device(rate: 24_000, transport: kAudioDeviceTransportTypeBluetooth)
        expectFalse(music == call) // Format monitoring must see enter and leave transitions.
    }

    func testCallBypassesNativeStartupEvenWithInvalidDevice() throws {
        // ID 0 cannot be opened: success proves the call gate runs before HAL capture setup.
        // AudioWorker still executes its real resource cleanup, without clearing mute choices.
        let worker = AudioWorker()
        let call = device(rate: 24_000, transport: kAudioDeviceTransportTypeBluetooth)
        let done = DispatchSemaphore(value: 0)
        let task = Task.detached {
            defer { done.signal() }
            do {
                let started = try await worker.start(device: call, automatic: true, volume: 0.3, trim: 8)
                expectFalse(started)
                let meter = try await worker.meters()
                expectEqual(meter.callbacks, 0)
                expectFalse(meter.formatFault)
                let apps = try await worker.applications()
                expectTrue(apps.allSatisfy { !$0.isMuted })
                try await worker.stop(clearApplicationMutes: true)
            } catch { fatalError("Call mode touched native startup: \(error)") }
        }
        expectEqual(done.wait(timeout: .now() + 5), .success)
        _ = task
    }
    func testTransitionDuringStartupPreservesIntentOnlyAfterCleanup() throws {
        enum Failure: Error { case startup, cleanup }
        var events: [String] = []
        let running = try ProcessingStartup.run(callMode: false, start: {
            events.append("start"); throw Failure.startup
        }, stop: { events.append("stop") }, currentCallMode: {
            events.append("read-mode"); return true
        })
        expectFalse(running)
        expectEqual(events, ["start", "stop", "read-mode"])
        events = []
        do {
            _ = try ProcessingStartup.run(callMode: false, start: { throw Failure.startup },
                stop: { throw Failure.cleanup }, currentCallMode: { events.append("read-mode"); return true })
            fatalError("Cleanup failure was hidden")
        } catch Failure.cleanup {} catch { fatalError("Unexpected error: \(error)") }
        expectTrue(events.isEmpty)
        do {
            _ = try ProcessingStartup.run(callMode: false, start: { throw Failure.startup },
                stop: {}, currentCallMode: { false })
            fatalError("Non-call startup failure was hidden")
        } catch Failure.startup {} catch { fatalError("Unexpected error: \(error)") }
        // Leaving call mode runs native startup again; successful startup never queries mode.
        expectTrue(try ProcessingStartup.run(callMode: false, start: {}, stop: { fatalError("Unexpected stop") },
            currentCallMode: { fatalError("Unexpected read") }))
    }

    func testPassthroughKeepsApplicationControlActiveWithoutDSP() throws {
        let router = AudioRouter()
        try router.startPassthrough(muted: [])
        expectTrue(router.isActive)
        expectFalse(router.isRunning)
        try router.setMutedProcesses([])
        try router.checkMuteHealth()
        expectEqual(router.meters.callbacks, 0)
        try router.stop()
        expectFalse(router.isActive)
        // Re-entering the mode and an empty target remain safe and require no tap.
        try router.startPassthrough(muted: [])
        expectTrue(router.isActive)
        try router.stop()
    }

    func testCallMuteDescriptionTargetsOnlySelectedProcessesAndDevice() {
        let description = Hardware.applicationMuteDescription([42, 43], deviceUID: "bluetooth-output")
        expectEqual(Set(description.processes), Set([UInt32(42), 43]))
        expectEqual(description.deviceUID, "bluetooth-output")
        expectEqual(description.stream, 0)
        expectFalse(description.isExclusive)
        expectFalse(description.isMixdown)
        expectTrue(description.isPrivate)
        expectEqual(description.muteBehavior, .muted)
    }

    func testCallTargetIsReadAfterStartupRecoveryAndRejectsMusicMode() throws {
        enum Failure: Error { case disconnected }
        let call = OutputDevice(id: 99, uid: "new-headset", name: "B", sampleRate: 24_000,
                                channels: 2, streamCount: 1, formatID: kAudioFormatLinearPCM,
                                formatFlags: kAudioFormatFlagIsFloat, bytesPerFrame: 8,
                                bitsPerChannel: 32, framesPerPacket: 1,
                                transportType: kAudioDeviceTransportTypeBluetooth)
        var latest = device(rate: 48_000, transport: kAudioDeviceTransportTypeBluetooth)
        let processing = try ProcessingStartup.run(callMode: false, start: {
            latest = call; throw Failure.disconnected
        }, stop: {}, currentCallMode: { latest.isBluetoothCallMode })
        expectFalse(processing)
        expectEqual(try ProcessingStartup.currentCallDeviceUID(read: { latest }), "new-headset")
        latest = device(rate: 48_000, transport: kAudioDeviceTransportTypeBluetooth)
        expectNil(try ProcessingStartup.currentCallDeviceUID(read: { latest }))
    }

}
