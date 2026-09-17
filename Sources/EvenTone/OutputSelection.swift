import Foundation

/// One request owns one listener. A setter returning success is not confirmation
/// that Core Audio has published the new default output yet.
protocol OutputSwitchBackend: AnyObject {
    func currentUID() throws -> String
    func request() throws
    func observe(_ changed: @escaping () -> Void) throws
    func stopObserving() throws
}

final class OutputSelection {
    private let targetUID: String
    private let backend: OutputSwitchBackend
    private var completion: ((Result<Void, Error>) -> Void)?

    init(targetUID: String, backend: OutputSwitchBackend) {
        self.targetUID = targetUID
        self.backend = backend
    }

    func start(_ completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        do {
            try backend.observe { [weak self] in self?.check() }
            if try backend.currentUID() != targetUID { try backend.request() }
            check()
        } catch { finish(.failure(error)) }
    }

    func timeout() {
        check()
        guard completion != nil else { return }
        finish(.failure(OutputSelectionError.notConfirmed))
    }

    private func check() {
        guard completion != nil else { return }
        do {
            if try backend.currentUID() == targetUID { finish(.success(())) }
        } catch { finish(.failure(error)) }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let completed = completion else { return }
        completion = nil
        do {
            try backend.stopObserving()
            completed(result)
        } catch { completed(.failure(error)) }
    }
}

enum OutputSelectionError: LocalizedError {
    case notConfirmed
    var errorDescription: String? {
        "系统尚未确认切换到所选设备，音频处理已停止。请检查设备连接后重新选择。"
    }
}
