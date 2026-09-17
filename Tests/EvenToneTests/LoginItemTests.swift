import Foundation
import ServiceManagement

private enum LoginTestError: Error { case denied }
private final class FakeLoginService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registeredStatus: SMAppService.Status = .enabled
    var failRegister = false
    var failUnregister = false
    var registrations = 0
    var cancellations = 0
    func register() throws {
        registrations += 1
        if failRegister { throw LoginTestError.denied }
        status = registeredStatus
    }
    func unregister() throws {
        cancellations += 1
        if failUnregister { throw LoginTestError.denied }
        status = .notRegistered
    }
}

final class LoginItemTests {
    func testRegistrationAndCancellationReadBackSystemStatus() throws {
        let service = FakeLoginService()
        let controller = LoginItemController(service: service)
        expectFalse(controller.isRegistered)
        controller.setEnabled(true)
        expectTrue(controller.isRegistered)
        controller.setEnabled(true)
        expectEqual(service.registrations, 1)
        controller.setEnabled(false)
        controller.setEnabled(false)
        expectFalse(controller.isRegistered)
        expectEqual(service.cancellations, 1)
    }

    func testFailedOperationsKeepActualSystemState() throws {
        let service = FakeLoginService()
        let controller = LoginItemController(service: service)
        service.failRegister = true
        controller.setEnabled(true)
        expectFalse(controller.isRegistered)
        expectTrue(controller.error != nil)
        service.failRegister = false
        controller.setEnabled(true)
        expectNil(controller.error)
        service.failUnregister = true
        controller.setEnabled(false)
        expectTrue(controller.isRegistered)
        expectTrue(controller.error != nil)
    }

    func testRequiresApprovalDoesNotClaimEffectiveOrRegisterAgain() throws {
        let service = FakeLoginService()
        service.registeredStatus = .requiresApproval
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        expectTrue(controller.needsApproval)
        expectTrue(controller.caption.contains("尚未生效"))
        controller.setEnabled(true)
        expectEqual(service.registrations, 1)
        controller.setEnabled(false)
        expectFalse(controller.isRegistered)
    }

    func testRefreshAndRelaunchRespectExternalChanges() throws {
        let service = FakeLoginService()
        service.status = .enabled
        let controller = LoginItemController(service: service)
        expectTrue(controller.isRegistered)
        service.status = .notRegistered
        controller.refresh()
        expectFalse(controller.isRegistered)
        service.status = .requiresApproval
        let reopened = LoginItemController(service: service)
        expectTrue(reopened.needsApproval)
        expectEqual(service.registrations, 0)
        service.status = .notFound
        reopened.refresh()
        expectFalse(reopened.isRegistered)
        expectTrue(reopened.caption.contains("不可用"))
    }
}
