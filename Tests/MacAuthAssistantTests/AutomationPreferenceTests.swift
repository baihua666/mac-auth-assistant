import XCTest
import AuthCore
@testable import MacAuthAssistant

final class AutomationPreferenceTests: XCTestCase {
    @MainActor
    func testEnabledPreferenceSurvivesRelaunchButExplicitPauseAlsoSurvives() throws {
        let suite = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = CredentialStore(service: suite)
        defer { try? store.delete() }
        try store.save(Credentials(account: "fixture", password: "fixture-value"))
        let initial = AppState(store: store, preferences: preferences, accessibilityCheck: { true })
        XCTAssertFalse(initial.enabled)
        initial.setEnabled(true)
        XCTAssertTrue(initial.enabled)
        let relaunched = AppState(store: store, preferences: preferences, accessibilityCheck: { true })
        XCTAssertTrue(relaunched.enabled)
        relaunched.setEnabled(false)
        XCTAssertFalse(AppState(store: store, preferences: preferences, accessibilityCheck: { true }).enabled)
    }

    @MainActor
    func testStoredPreferenceCannotEnableWithoutPermissionOrCredentials() throws {
        let suite = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = CredentialStore(service: suite)
        defer { try? store.delete() }
        preferences.set(true, forKey: "automaticProcessingEnabled")
        XCTAssertFalse(AppState(store: store, preferences: preferences, accessibilityCheck: { true }).enabled)
        try store.save(Credentials(account: "fixture", password: "fixture-value"))
        XCTAssertFalse(AppState(store: store, preferences: preferences, accessibilityCheck: { false }).enabled)
        XCTAssertTrue(AppState(store: store, preferences: preferences, accessibilityCheck: { true }).enabled)
    }
}
