import XCTest
@testable import MacAuthAssistant

final class LoginItemControllerTests: XCTestCase {
    @MainActor
    func testRegistersOnceAndRespectsLaterSystemDisable() throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let service = FixtureLoginService()
        let controller = LoginItemController(preferences: preferences, service: service)
        controller.configureOnLaunch()
        XCTAssertEqual(controller.state, .enabled)
        XCTAssertEqual(service.registrations, 1)
        service.state = .disabled // User disables the entry in System Settings.
        let relaunched = LoginItemController(preferences: preferences, service: service)
        relaunched.configureOnLaunch()
        XCTAssertEqual(relaunched.state, .disabled)
        XCTAssertEqual(service.registrations, 1)
        relaunched.setEnabled(true)
        XCTAssertEqual(service.registrations, 2)
        relaunched.setEnabled(false)
        XCTAssertEqual(service.unregistrations, 1)
        XCTAssertEqual(relaunched.state, .disabled)
    }

    @MainActor
    func testRequiresApprovalIsNotReportedAsEnabled() throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let service = FixtureLoginService()
        service.registrationResult = .requiresApproval
        let controller = LoginItemController(preferences: preferences, service: service)
        controller.configureOnLaunch()
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertFalse(controller.isEnabled)
        controller.configureOnLaunch()
        XCTAssertEqual(service.registrations, 1)
    }

    @MainActor
    func testRegistrationFailureIsVisibleAndDoesNotRetryEachLaunch() throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let service = FixtureLoginService()
        service.failure = NSError(domain: "fixture", code: 17)
        let controller = LoginItemController(preferences: preferences, service: service)
        controller.configureOnLaunch()
        XCTAssertEqual(controller.state, .disabled)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(controller.errorCode, 17)
        controller.configureOnLaunch()
        XCTAssertEqual(service.registrations, 1)
    }
}

@MainActor
private final class FixtureLoginService: LoginItemService {
    var state: LoginItemState = .disabled
    var registrationResult: LoginItemState = .enabled
    var failure: Error?
    var registrations = 0
    var unregistrations = 0
    func register() throws {
        registrations += 1
        if let failure { throw failure }
        state = registrationResult
    }
    func unregister() throws { unregistrations += 1; state = .disabled }
}
