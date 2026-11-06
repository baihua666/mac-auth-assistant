import XCTest
@testable import AuthCore

final class AutomationConditionsTests: XCTestCase {
    func testSettingsWindowDoesNotPauseOtherwiseReadyAutomation() {
        let conditions = AutomationConditions(enabled: true, hasCredentials: true,
                                              accessibilityGranted: true, suspended: false,
                                              settingsVisible: true)
        XCTAssertTrue(conditions.isReady)
    }

    func testClosingSettingsDoesNotRestartOrConsumeCountdown() {
        var gate = CountdownGate()
        var conditions = AutomationConditions(enabled: true, hasCredentials: true,
                                              accessibilityGranted: true, suspended: false,
                                              settingsVisible: true)
        XCTAssertEqual(gate.observe(target: "A", enabled: conditions.isReady, delay: 2, now: 0), .countdown(2))
        conditions.settingsVisible = false
        XCTAssertEqual(gate.observe(target: "A", enabled: conditions.isReady, delay: 2, now: 1), .countdown(1))
        XCTAssertEqual(gate.observe(target: "A", enabled: conditions.isReady, delay: 2, now: 2), .submit("A"))
    }

    func testRealPauseMissingCredentialsAndPermissionStillBlockProcessing() {
        XCTAssertFalse(AutomationConditions(enabled: false, hasCredentials: true, accessibilityGranted: true,
                                            suspended: false, settingsVisible: false).isReady)
        XCTAssertFalse(AutomationConditions(enabled: true, hasCredentials: false, accessibilityGranted: true,
                                            suspended: false, settingsVisible: false).isReady)
        XCTAssertFalse(AutomationConditions(enabled: true, hasCredentials: true, accessibilityGranted: false,
                                            suspended: false, settingsVisible: false).isReady)
        XCTAssertFalse(AutomationConditions(enabled: true, hasCredentials: true, accessibilityGranted: true,
                                            suspended: true, settingsVisible: false).isReady)
    }
}
