import XCTest
import AuthCore
import ApplicationServices
@testable import MacAuthAssistant

final class ActivityHistoryTests: XCTestCase {
    @MainActor
    func testAdministratorPreflightReadsCurrentBlacklistAndCanBeUnblocked() throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let history = ActivityHistory()
        let store = CredentialStore(service: name)
        let state = AppState(store: store, preferences: preferences, activity: history)
        let node = AXUIElementCreateSystemWide()
        let dialog = DetectedDialog(id: "fixture", pid: 0, window: node, password: node, account: nil, accountValue: "",
                                    submitElement: node, submitAction: kAXPressAction, context: "Used by Sample to perform its helper task.",
                                    facts: DialogFacts(trustedProvider: true, passwordFields: 1, accountFields: 0,
                                                       canWritePassword: true, canSubmit: true, passwordIsEmpty: true), isNewWindow: true)
        XCTAssertNil(state.rejection(for: dialog))
        let rule = BlockRule(exactRequest: dialog.activityRequest)
        try history.saveRule(rule)
        XCTAssertTrue(state.rejection(for: dialog)?.contains("命中黑名单") == true)
        XCTAssertTrue(state.administratorBlocked(dialog))
        XCTAssertEqual(history.records.first?.outcome, .ignored)
        history.setRuleEnabled(rule.id, enabled: false)
        XCTAssertNil(state.rejection(for: dialog))
    }
    @MainActor
    func testCorruptBlacklistCannotSilentlyBecomeAllowAllOrBeOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("activity.json")
        let original = Data("not valid JSON".utf8)
        try original.write(to: path)
        let history = ActivityHistory(destination: path)
        XCTAssertTrue(history.loadFailed)
        let request = ActivityRequest(kind: .administrator, context: "Sample wants to make changes")
        XCTAssertTrue(history.checkBlocked(token: "A", request: request, text: ""))
        XCTAssertEqual(try Data(contentsOf: path), original)
        XCTAssertThrowsError(try history.saveRule(BlockRule(exactRequest: request)))
        XCTAssertEqual(try Data(contentsOf: path), original)
    }
    @MainActor
    func testHistoryDeduplicatesPollingAndPersistsRulesAndTerminalResults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("activity.json")
        let history = ActivityHistory(destination: path)
        let request = ActivityRequest(kind: .permission, context: "“Sample”想要访问麦克风。", category: .microphone)
        for _ in 0..<10 { history.observe(token: "A", request: request) }
        XCTAssertEqual(history.records.count, 1)
        history.finish(token: "A", outcome: .submitted, reason: "已发送，等待结果")
        history.finish(token: "A", outcome: .success, reason: "弹窗已关闭，原任务未验证")
        try history.saveRule(BlockRule(exactRequest: request))
        try history.saveRule(BlockRule(exactRequest: request))
        XCTAssertEqual(history.rules.count, 1)
        let restored = ActivityHistory(destination: path)
        XCTAssertEqual(restored.records.first?.outcome, .success)
        XCTAssertNotNil(restored.blockingRule(for: request, text: ""))
        let rule = try XCTUnwrap(restored.rules.first)
        restored.setRuleEnabled(rule.id, enabled: false)
        XCTAssertNil(restored.blockingRule(for: request, text: ""))
        restored.clearRecords()
        XCTAssertEqual(restored.rules.count, 1)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int, 0o600)
    }
    @MainActor
    func testPendingAfterRestartIsNotReportedAsSuccessAndIgnoredIsRecordedOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("activity.json")
        let history = ActivityHistory(destination: path)
        let request = ActivityRequest(kind: .administrator, context: "Sample wants to make changes")
        history.observe(token: "A", request: request)
        let restored = ActivityHistory(destination: path)
        XCTAssertEqual(restored.records.first?.outcome, .ignored)
        restored.observe(token: "B", request: request)
        for _ in 0..<10 { restored.finish(token: "B", outcome: .ignored, reason: "命中黑名单") }
        XCTAssertEqual(restored.records.count, 2)
        XCTAssertEqual(restored.records.first?.reason, "命中黑名单")
        restored.clearRecords()
        XCTAssertTrue(restored.records.isEmpty)
    }
}
