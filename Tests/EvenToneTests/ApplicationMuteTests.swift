import Foundation

final class ApplicationMuteTests {
    private let chrome = AudioApplication(id: "/Applications/Chrome.app", name: "Chrome", processIDs: [11, 12], isActive: true)
    private let safari = AudioApplication(id: "/Applications/Safari.app", name: "Safari", processIDs: [21], isActive: true)

    func testBrowserHelpersAndDistinctApps() {
        let url = URL(fileURLWithPath: "/Applications/Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper")
        expectEqual(ApplicationMuteState.owningApplication(at: url)?.path, "/Applications/Chrome.app")
        expectNil(ApplicationMuteState.owningApplication(at: URL(fileURLWithPath: "/usr/bin/player")))
        let helper = AudioApplication(id: chrome.id, name: chrome.name, processIDs: [13], isActive: false)
        let grouped = ApplicationMuteState.group([chrome, safari, helper])
        expectEqual(grouped.count, 2)
        expectEqual(grouped.first { $0.id == chrome.id }?.processIDs, [11, 12, 13])
        expectTrue(grouped.first { $0.id == chrome.id }!.isActive)
    }

    func testIndependentMuteRestoreAndClear() {
        var state = ApplicationMuteState()
        var target: Set<UInt32> = []
        state.set(chrome, muted: true, applications: [chrome, safari]) { target = $0 }
        expectEqual(target, [11, 12])
        expectFalse(state.rows([chrome, safari]).first { $0.id == safari.id }!.isMuted)
        state.set(safari, muted: true, applications: [chrome, safari]) { target = $0 }
        expectEqual(target, [11, 12, 21])
        state.set(chrome, muted: false, applications: [chrome, safari]) { target = $0 }
        expectEqual(target, [21])
        state.clear()
        expectEqual(state.processIDs(in: [chrome, safari]), [])
        expectTrue(state.rows([chrome, safari]).allSatisfy { !$0.isMuted })
        expectEqual(ApplicationMuteState().selected.count, 0)
    }

    func testProcessTurnoverAndIdleSelection() {
        var state = ApplicationMuteState()
        state.set(chrome, muted: true, applications: [chrome]) { _ in }
        let idleRows = state.rows([])
        expectEqual(idleRows.count, 1)
        expectTrue(idleRows[0].isMuted)
        expectFalse(idleRows[0].isActive)
        expectEqual(state.processIDs(in: []), [])
        let replacement = AudioApplication(id: chrome.id, name: chrome.name, processIDs: [33], isActive: true)
        expectEqual(state.processIDs(in: [replacement, safari]), [33])
        state.set(idleRows[0], muted: false, applications: []) { expectEqual($0, []) }
        expectEqual(state.rows([]), [])
        var inactive = safari
        inactive.isActive = false
        expectEqual(state.rows([inactive]), [])
    }

    func testPartialRoutingFailureCleansAndStaysVisible() throws {
        enum Failure: Error { case hal, cleanup }
        for failedStep in 1...3 {
            let state = ProcessMuteRoutingState()
            state.reset(applied: [11])
            var step = 0
            var cleaned = false
            let operation: (Set<UInt32>) throws -> Void = { _ in
                step += 1
                if step == failedStep { throw Failure.hal }
            }
            do {
                try state.update([11, 12], suppress: operation, exclude: operation) {
                    cleaned = true
                    state.reset() // AudioRouter.stop resets after successful teardown.
                }
                fatalError("Partial HAL failure swallowed")
            } catch {}
            expectTrue(cleaned)
            // Even if UI discards the first response, the next poll must observe failure.
            do { try state.checkHealth(); fatalError("Lost sticky error") } catch {}
            do {
                try state.update([11, 12], suppress: { _ in fatalError("Used failed route") },
                                 exclude: { _ in }, cleanup: {})
                fatalError("Failed route reused")
            } catch {}
            state.reset()
            try state.checkHealth()
            expectEqual(state.applied, [])
        }
        let state = ProcessMuteRoutingState()
        do {
            try state.update([11], suppress: { _ in throw Failure.hal }, exclude: { _ in },
                             cleanup: { throw Failure.cleanup })
            fatalError("Cleanup failure swallowed")
        } catch { expectTrue(error.localizedDescription.contains("\n")) }
    }

    func testRoutingTransitionOrderAndNoOp() throws {
        let state = ProcessMuteRoutingState()
        state.reset(applied: [11])
        var events: [String] = []
        try state.update([21], suppress: { events.append("suppress:\($0.sorted())") },
                         exclude: { events.append("exclude:\($0.sorted())") }, cleanup: { fatalError("Unexpected cleanup") })
        expectEqual(events, ["suppress:[11, 21]", "exclude:[21]", "suppress:[21]"])
        expectEqual(state.applied, [21])
        try state.update([21], suppress: { _ in fatalError("Repeated operation") }, exclude: { _ in }, cleanup: {})
        try state.update([], suppress: { _ in }, exclude: { expectEqual($0, []) }, cleanup: {})
        expectEqual(state.applied, [])
    }

    func testFailureDoesNotCommitSelection() {
        enum Failure: Error { case hal }
        var state = ApplicationMuteState()
        do {
            try state.set(chrome, muted: true, applications: [chrome]) { _ in throw Failure.hal }
            fatalError("HAL failure swallowed")
        } catch {}
        expectTrue(state.selected.isEmpty)
        state.set(chrome, muted: true, applications: [chrome]) { _ in }
        do {
            try state.set(chrome, muted: false, applications: [chrome]) { _ in throw Failure.hal }
            fatalError("HAL failure swallowed")
        } catch {}
        expectTrue(state.rows([chrome])[0].isMuted)
    }
}
