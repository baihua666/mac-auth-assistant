import XCTest
@testable import AuthCore

final class ActivityRuleTests: XCTestCase {
    func testExactTaskRuleDoesNotBlockOtherRequestsFromSameApplication() {
        let first = ActivityRequest(kind: .administrator, context: "Used by vphone-launchpad to run its privileged helper as root.")
        let second = ActivityRequest(kind: .administrator, context: "Used by vphone-launchpad to repair a different service.")
        let rule = BlockRule(exactRequest: first)
        XCTAssertTrue(rule.matches(first, text: ""))
        XCTAssertFalse(rule.matches(second, text: ""))
        XCTAssertEqual(first.application, "vphone-launchpad")
        XCTAssertEqual(ActivityRequest(kind: .permission, context: "允许“Permission Check”查找本地网络上的设备？", category: .localNetwork).application, "Permission Check")
    }
    func testKeywordTypeAndCategoryMustAllMatchAndDisabledRulesDoNothing() {
        let request = ActivityRequest(kind: .permission, context: "“Sample”想要访问麦克风。", category: .microphone)
        var rule = BlockRule(name: "特定任务", kind: .permission, category: .microphone, keyword: "SAMPLE")
        XCTAssertTrue(rule.matches(request, text: "Sample requests microphone"))
        XCTAssertFalse(rule.matches(request, text: "Another requests microphone"))
        rule.kind = .administrator
        XCTAssertFalse(rule.matches(request, text: "Sample requests microphone"))
        rule.kind = .permission; rule.enabled = false
        XCTAssertFalse(rule.matches(request, text: "Sample requests microphone"))
    }
    func testEmptyCatchAllRulesAreInvalidAndSummaryOmitsCredentialPrompt() throws {
        XCTAssertFalse(BlockRule(name: "空规则").isValid)
        let request = ActivityRequest(kind: .administrator, context: "Sample is trying to make changes.\nEnter the password for user private-account")
        let encoded = try JSONEncoder().encode(request)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private-account"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("Enter the password"))
        XCTAssertNotEqual(request.taskKey, ActivityRequest(kind: .administrator, context: "different").taskKey)
    }
}
