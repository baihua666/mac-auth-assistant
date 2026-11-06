import XCTest
@testable import AuthCore

final class FocusRecoveryTests: XCTestCase {
    func testFocusLossRestartsFullCountdownWithoutRepeatingConsumedSubmission() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 3, now: 0)
        gate.pauseForFocusLoss()
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 1), .countdown(3))
        XCTAssertEqual(gate.submitNow(), "A")
        gate.pauseForFocusLoss()
        XCTAssertTrue(gate.isSuppressed("A"))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 2), .idle)
    }

    func testExplicitCancellationCannotBeUndoneByFocusRecovery() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 3, now: 0)
        gate.cancel()
        gate.pauseForFocusLoss()
        XCTAssertTrue(gate.isSuppressed("A"))
    }

    func testFocusAttemptsAreBoundedAndWaitForInputToSettle() {
        var gate = FocusRecoveryGate()
        XCTAssertFalse(gate.request("A", now: 10, lastInput: 9.5))
        XCTAssertTrue(gate.request("A", now: 11, lastInput: 9.5))
        XCTAssertFalse(gate.request("A", now: 11.5, lastInput: 9.5))
        XCTAssertTrue(gate.request("A", now: 12, lastInput: 9.5))
        XCTAssertFalse(gate.request("A", now: 14, lastInput: 9.5))
        gate.retain(visible: [])
        XCTAssertTrue(gate.request("A", now: 15, lastInput: 9.5))
    }
}
