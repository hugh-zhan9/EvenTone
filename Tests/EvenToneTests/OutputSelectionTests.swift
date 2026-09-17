import Foundation

private enum SwitchTestError: Error { case failed }

private final class FakeOutputBackend: OutputSwitchBackend {
    var uid = "old"
    var immediate = false
    var failRequest = false
    var failRead = false
    var failObserve = false
    var failCleanup = false
    var requests = 0
    var removals = 0
    var changed: (() -> Void)?
    func currentUID() throws -> String {
        if failRead { throw SwitchTestError.failed }
        return uid
    }
    func request() throws {
        requests += 1
        if failRequest { throw SwitchTestError.failed }
        if immediate { uid = "new"; changed?() }
    }
    func observe(_ changed: @escaping () -> Void) throws {
        if failObserve { throw SwitchTestError.failed }
        self.changed = changed
    }
    func stopObserving() throws {
        removals += 1
        if failCleanup { throw SwitchTestError.failed }
        changed = nil
    }
}

final class OutputSelectionTests {
    func testWaitsForConfirmationAndCompletesOnce() throws {
        let backend = FakeOutputBackend()
        let request = OutputSelection(targetUID: "new", backend: backend)
        var completions = 0
        request.start { result in
            guard case .success = result else { fatalError("Expected confirmation success") }
            completions += 1
        }
        expectEqual(completions, 0) // Setter succeeded, but the published default is still old.
        expectEqual(backend.requests, 1)
        let lateNotification = backend.changed
        backend.uid = "new"
        backend.changed?()
        request.timeout()
        lateNotification?()
        expectEqual(completions, 1)
        expectEqual(backend.removals, 1)
    }

    func testSynchronousConfirmationAndAlreadySelectedDevice() throws {
        for alreadySelected in [false, true] {
            let backend = FakeOutputBackend()
            backend.immediate = true
            if alreadySelected { backend.uid = "new" }
            let request = OutputSelection(targetUID: "new", backend: backend)
            var complete = false
            request.start { result in
                guard case .success = result else { fatalError("Expected success") }
                complete = true
            }
            expectTrue(complete)
            expectEqual(backend.requests, alreadySelected ? 0 : 1)
            expectEqual(backend.removals, 1)
        }
    }

    func testUnconfirmedSwitchTimesOutWithoutRetryOrRollback() throws {
        let backend = FakeOutputBackend()
        let request = OutputSelection(targetUID: "new", backend: backend)
        var failures = 0
        request.start { result in
            guard case .failure = result else { fatalError("Must not report an unconfirmed switch as success") }
            failures += 1
        }
        let lateNotification = backend.changed
        request.timeout()
        backend.uid = "new"
        lateNotification?()
        expectEqual(failures, 1)
        expectEqual(backend.requests, 1)
        expectEqual(backend.uid, "new")
        expectEqual(backend.removals, 1)
    }

    func testMissingDefaultCanBeReplacedAndLateConfirmationAtDeadline() throws {
        let backend = FakeOutputBackend()
        backend.uid = ""
        let request = OutputSelection(targetUID: "new", backend: backend)
        var confirmed = false
        request.start { result in
            guard case .success = result else { fatalError("Read-back confirmed the requested device") }
            confirmed = true
        }
        backend.uid = "new" // Simulate an updated property whose listener delivery was delayed.
        request.timeout()
        expectTrue(confirmed)
    }

    func testReadRequestAndListenerErrorsAreNotSuccess() throws {
        for scenario in 0..<4 {
            let backend = FakeOutputBackend()
            backend.failRead = scenario == 0
            backend.failRequest = scenario == 1
            backend.failObserve = scenario == 2
            backend.failCleanup = scenario == 3
            backend.immediate = scenario == 3
            let request = OutputSelection(targetUID: "new", backend: backend)
            var failed = false
            request.start { result in
                guard case .failure = result else { fatalError("Expected native operation error") }
                failed = true
            }
            expectTrue(failed)
            expectEqual(backend.removals, 1)
        }
    }
}
