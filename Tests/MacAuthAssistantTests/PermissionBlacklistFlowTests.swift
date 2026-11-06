import XCTest
import ApplicationServices
import AuthCore
@testable import MacAuthAssistant

@MainActor
private final class PermissionWindowFixture: PermissionScanning {
    var windows: [PermissionWindow] = []
    let providerCount = 1
    let trustedProviderCount = 1
    let windowReadCodes: [Int32] = [0]
    func scan() -> [PermissionWindow] { windows }
    init() {
        let node = AXUIElementCreateSystemWide() // Inert identity only; never queried or pressed.
        let context = "“History Flow Fixture”想要访问本地网络。"
        let decision = PermissionPolicy.decide(PermissionFacts(trustedProvider: true, passwordFields: 0,
            text: context, buttons: [AuthButton(labels: ["允许"], supportsPress: true)]))
        windows = [PermissionWindow(id: "same-visible-window", pid: 0, window: node, context: context,
                                    decision: decision, button: node)]
    }
}

final class PermissionBlacklistFlowTests: XCTestCase {
    @MainActor
    func testHistoryBlockStopsRealCoordinatorAndUnblockResumesSameWindow() async throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { prefs.removePersistentDomain(forName: name) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let history = ActivityHistory(destination: dir.appendingPathComponent("activity.json"))
        let scanner = PermissionWindowFixture()
        let window = try XCTUnwrap(scanner.windows.first)
        var presses = 0
        let coordinator = PermissionAutomation(preferences: prefs, activity: history, scanner: scanner,
            journal: PermissionJournal(destination: dir.appendingPathComponent("permissions.json")),
            accessibilityCheck: { true }, pressButton: { _ in presses += 1; return .success })
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        XCTAssertEqual(coordinator.remaining, 1)
        let record = try XCTUnwrap(history.records.first)
        try history.setRequestBlocked(record.request, blocked: true) // Same command as the history button.
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        XCTAssertNil(coordinator.remaining)
        XCTAssertEqual(history.records.first?.outcome, .ignored)
        XCTAssertTrue(history.records.first?.reason.contains("命中黑名单") == true)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(history.records.count, 1)
        try history.setRequestBlocked(record.request, blocked: false)
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        XCTAssertEqual(coordinator.remaining, 1) // Full countdown, not immediate confirmation.
        XCTAssertEqual(scanner.windows.first?.id, window.id)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(history.records.first?.outcome, .submitted)
        scanner.windows = []
        try await Task.sleep(nanoseconds: 3_200_000_000)
        XCTAssertEqual(history.records.map(\.outcome), [.success, .ignored])
        XCTAssertEqual(history.records.last?.ruleID, history.requestRule(for: record.request)?.id)
        let restored = ActivityHistory(destination: dir.appendingPathComponent("activity.json"))
        XCTAssertFalse(restored.isRequestBlocked(record.request))
        XCTAssertEqual(restored.records.map(\.outcome), [.success, .ignored])
    }
    @MainActor
    func testExplicitCancellationIsNotUndoneByHistoryToggle() async throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { prefs.removePersistentDomain(forName: name) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let history = ActivityHistory()
        let scanner = PermissionWindowFixture()
        let request = try XCTUnwrap(scanner.windows.first?.activityRequest)
        var presses = 0
        let coordinator = PermissionAutomation(preferences: prefs, activity: history, scanner: scanner,
            journal: PermissionJournal(destination: dir.appendingPathComponent("permissions.json")),
            accessibilityCheck: { true }, pressButton: { _ in presses += 1; return .success })
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        coordinator.cancelCurrent()
        try history.setRequestBlocked(request, blocked: true)
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        try history.setRequestBlocked(request, blocked: false)
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        coordinator.tick(allowed: true, delay: 1, lastInput: -.infinity)
        XCTAssertNil(coordinator.remaining)
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(history.records.count, 1)
    }
}
