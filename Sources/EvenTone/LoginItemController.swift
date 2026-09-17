import Combine
import Foundation
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Used on the main thread. State is always read from macOS, never from UserDefaults.
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error: String?
    private let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp) {
        self.service = service
        status = service.status
    }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }
    var caption: String {
        switch status {
        case .enabled: return "已开启 · 登录 Mac 后自动打开应用"
        case .requiresApproval: return "等待系统允许，尚未生效"
        case .notRegistered: return "登录 Mac 后自动打开应用"
        case .notFound: return "登录项不可用，请从打包的应用运行"
        @unknown default: return "无法确认登录项状态"
        }
    }

    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) {
        error = nil
        refresh()
        do {
            if enabled {
                // A previously denied registration needs system approval, not another register.
                if !isRegistered { try service.register() }
            } else if isRegistered {
                try service.unregister()
            }
        } catch { self.error = "无法更新登录项：\(error.localizedDescription)" }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
