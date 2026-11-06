import XCTest
import AuthCore
@testable import MacAuthAssistant

final class RuntimeDiagnosticsTests: XCTestCase {
    @MainActor
    func testRecordsBackgroundBlockingReasonAndSubmissionWithoutCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("runtime.json")
        let diagnostics = RuntimeDiagnostics(destination: destination)
        let conditions = AutomationConditions(enabled: true, hasCredentials: true,
                                              accessibilityGranted: true, suspended: false, settingsVisible: true)
        var observation = ValidationObservation()
        observation.windows = 1
        diagnostics.observe(conditions: conditions, observation: observation,
                            block: .notFocused, rejection: nil, remaining: nil)
        diagnostics.record(.confirmationSent)
        diagnostics.recordInteraction(cancelled: false, offset: -0.01)
        diagnostics.recordLoginItem(.requiresApproval)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: destination)) as? [String: Any])
        XCTAssertEqual(json["block"] as? String, "notFocused")
        XCTAssertEqual(json["lastAction"] as? String, "confirmationSent")
        XCTAssertEqual(json["interactionCancelled"] as? Bool, false)
        XCTAssertEqual(json["interactionOffsetSeconds"] as? Double, -0.01)
        XCTAssertEqual(json["loginItemState"] as? String, "requiresApproval")
        XCTAssertNil(json["password"])
        XCTAssertNil(json["account"])
        XCTAssertNil(json["context"])
        let mode = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertFalse(diagnostics.persistenceFailed)
    }
}
