import XCTest
import AuthCore
import ApplicationServices
@testable import MacAuthAssistant

final class CredentialStoreTests: XCTestCase {
    func testKeychainCreateUpdateReadAndDeleteAreIsolated() throws {
        let store = CredentialStore(service: "local.mac-auth-assistant.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        XCTAssertNil(try store.load())
        try store.save(Credentials(account: "fixture-admin", password: " first fixture value "))
        XCTAssertEqual(try store.load()?.account, "fixture-admin")
        XCTAssertEqual(try store.load()?.password, " first fixture value ")
        try store.save(Credentials(account: "other-fixture", password: "replacement fixture"))
        XCTAssertEqual(try store.load()?.account, "other-fixture")
        XCTAssertEqual(try store.load()?.password, "replacement fixture")
        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testNonSystemApplicationIsNotAcceptedAsAnAuthenticationProvider() {
        XCTAssertFalse(SystemAuthenticationProvider.isTrusted(.current))
    }

    func testUnreadableInputStateIsNotTreatedAsAnEmptyPassword() {
        XCTAssertEqual(AX.inputState(AXUIElementCreateSystemWide()), .unknown)
    }

    @MainActor
    func testSavedCredentialsCanBeReloadedWithoutReenteringPassword() throws {
        let store = CredentialStore(service: "local.mac-auth-assistant.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        let state = AppState(store: store)
        XCTAssertFalse(state.hasCredentials)
        try store.save(Credentials(account: "saved-fixture", password: "fixture-value"))
        XCTAssertTrue(state.restoreSavedCredentials())
        XCTAssertTrue(state.hasCredentials)
        XCTAssertEqual(state.account, "saved-fixture")
        XCTAssertFalse(state.enabled)
    }

    @MainActor
    func testReloadWithoutStoredCredentialsDoesNotClaimSuccess() {
        let store = CredentialStore(service: "local.mac-auth-assistant.tests.\(UUID().uuidString)")
        let state = AppState(store: store)
        XCTAssertFalse(state.restoreSavedCredentials())
        XCTAssertFalse(state.hasCredentials)
        XCTAssertFalse(state.enabled)
    }
}
