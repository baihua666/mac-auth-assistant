import XCTest
@testable import AuthCore

final class BlacklistCountdownTests: XCTestCase {
    func testBlockDuringCountdownThenUnblockSameVisibleWindowRestartsFullDelay() {
        var gate = CountdownGate()
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 0), .countdown(3))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 1), .countdown(2))
        XCTAssertTrue(gate.pauseIfBlocked(["A"]))
        XCTAssertFalse(gate.isSuppressed("A"))
        XCTAssertEqual(gate.observe(target: nil, enabled: true, delay: 3, now: 2, visible: ["A"]), .idle)
        XCTAssertEqual(gate.observe(target: nil, enabled: true, delay: 3, now: 3, visible: ["A"]), .idle)
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 4, visible: ["A"]), .countdown(3))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 5), .countdown(2))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 6), .countdown(1))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 7), .submit("A"))
    }
    func testBlacklistChangesDoNotReviveExplicitlyCancelledOrSubmittedWindows() {
        for submit in [false, true] {
            var gate = CountdownGate()
            _ = gate.observe(target: "A", enabled: true, delay: 3, now: 0)
            if submit { _ = gate.submitNow() } else { gate.cancel() }
            XCTAssertFalse(gate.pauseIfBlocked(["A"]))
            XCTAssertTrue(gate.isSuppressed("A"))
            XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 1), .idle)
        }
    }
    func testUnrelatedBlacklistRuleDoesNotInterruptCountdown() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 3, now: 0)
        XCTAssertFalse(gate.pauseIfBlocked(["B"]))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 1), .countdown(2))
    }
}
