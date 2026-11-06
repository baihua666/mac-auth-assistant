import XCTest
import AuthCore
@testable import MacAuthAssistant

final class HistoryBlacklistTests: XCTestCase {
    @MainActor
    func testOneClickFromHistoryPersistsWithoutDuplicatesOrChangingResults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("activity.json")
        let history = ActivityHistory(destination: path)
        let request = ActivityRequest(kind: .permission, context: "“Sample”想要访问麦克风。", category: .microphone)
        history.observe(token: "window", request: request)
        history.finish(token: "window", outcome: .success, reason: "原有结果")
        let record = try XCTUnwrap(history.records.first)
        for _ in 0..<5 { try history.setRequestBlocked(record.request, blocked: true) }
        XCTAssertEqual(history.rules.count, 1)
        XCTAssertTrue(history.isRequestBlocked(record.request))
        XCTAssertNotNil(history.blockingRule(for: record.request, text: ""))
        XCTAssertEqual(history.records.first?.outcome, .success)
        XCTAssertEqual(history.records.first?.reason, "原有结果")
        let other = ActivityRequest(kind: .permission, context: "“Sample”想要使用相机。", category: .camera)
        XCTAssertNil(history.blockingRule(for: other, text: ""))
        let restored = ActivityHistory(destination: path)
        XCTAssertTrue(restored.isRequestBlocked(record.request))
        let id = restored.requestRule(for: record.request)?.id
        try restored.setRequestBlocked(record.request, blocked: false)
        XCTAssertFalse(restored.isRequestBlocked(record.request))
        XCTAssertNil(restored.blockingRule(for: record.request, text: ""))
        try restored.setRequestBlocked(record.request, blocked: true)
        XCTAssertEqual(restored.rules.count, 1)
        XCTAssertEqual(restored.requestRule(for: record.request)?.id, id)
    }
    @MainActor
    func testReusesDisabledRuleAndRemovalDoesNotDisableBroaderRules() throws {
        let history = ActivityHistory()
        let request = ActivityRequest(kind: .permission, context: "“Sample”想要访问麦克风。", category: .microphone)
        var rule = BlockRule(exactRequest: request); rule.name = "原规则名称"; rule.enabled = false
        try history.saveRule(rule)
        try history.setRequestBlocked(request, blocked: true)
        XCTAssertEqual(history.requestRule(for: request)?.id, rule.id)
        XCTAssertEqual(history.requestRule(for: request)?.name, "原规则名称")
        let broader = BlockRule(name: "所有麦克风请求", kind: .permission, category: .microphone)
        try history.saveRule(broader)
        try history.setRequestBlocked(request, blocked: false)
        XCTAssertFalse(history.isRequestBlocked(request))
        XCTAssertEqual(history.blockingRule(for: request, text: "")?.id, broader.id)
    }
    @MainActor
    func testIncompleteRecordsCannotCreateBroadWildcardRules() throws {
        let history = ActivityHistory()
        let legacy = ActivityRequest(kind: .permission, context: "", category: .localNetwork)
        XCTAssertThrowsError(try history.setRequestBlocked(legacy, blocked: true))
        XCTAssertTrue(history.rules.isEmpty)
        XCTAssertFalse(history.isRequestBlocked(legacy))
    }
    @MainActor
    func testFailedSaveDoesNotReportAddedOrRemoveExistingProtection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("activity.json")
        let history = ActivityHistory(destination: path)
        let request = ActivityRequest(kind: .administrator, context: "Sample wants to make changes")
        try history.setRequestBlocked(request, blocked: true)
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        XCTAssertThrowsError(try history.setRequestBlocked(request, blocked: false))
        XCTAssertTrue(history.isRequestBlocked(request))
        XCTAssertTrue(history.persistenceFailed)
        let other = ActivityRequest(kind: .administrator, context: "Another wants to make changes")
        XCTAssertThrowsError(try history.setRequestBlocked(other, blocked: true))
        XCTAssertFalse(history.isRequestBlocked(other))
        XCTAssertEqual(history.rules.count, 1)
    }
}
