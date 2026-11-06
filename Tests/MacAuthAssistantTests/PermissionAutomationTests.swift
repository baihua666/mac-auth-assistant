import XCTest
@testable import MacAuthAssistant

final class PermissionAutomationTests: XCTestCase {
    @MainActor
    func testPermissionSwitchPersistsIndependentlyOfPasswordAutomation() throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(false, forKey: "automaticProcessingEnabled")
        let controller = PermissionAutomation(preferences: preferences)
        XCTAssertTrue(controller.enabled)
        controller.setEnabled(false)
        XCTAssertFalse(PermissionAutomation(preferences: preferences).enabled)
        controller.setEnabled(true)
        XCTAssertTrue(PermissionAutomation(preferences: preferences).enabled)
        XCTAssertFalse(preferences.bool(forKey: "automaticProcessingEnabled"))
    }

    @MainActor
    func testJournalIsBoundedPrivateAndReportsWriteFailures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("permissions.json")
        let journal = PermissionJournal(destination: destination)
        for _ in 0..<55 { journal.record(.sent, category: .localNetwork) }
        journal.observe(enabled: true, windows: 1, remaining: 5)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: destination)) as? [String: Any])
        XCTAssertEqual((json["events"] as? [[String: Any]])?.count, 50)
        XCTAssertNil(json["password"]); XCTAssertNil(json["context"])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertFalse(journal.persistenceFailed)
        let relaunched = PermissionJournal(destination: destination)
        relaunched.observe(enabled: false, windows: 0, remaining: nil)
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: destination)) as? [String: Any])
        XCTAssertEqual((restored["events"] as? [[String: Any]])?.count, 50)
        let invalid = PermissionJournal(destination: destination.appendingPathComponent("impossible.json"))
        invalid.record(.failed, category: .files)
        XCTAssertTrue(invalid.persistenceFailed)
    }
}
