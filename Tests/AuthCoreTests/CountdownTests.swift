import XCTest
@testable import AuthCore

final class CountdownTests: XCTestCase {
    func testDelayedFocusClickBeforeCountdownDoesNotCancelNewCountdown() {
        var gate = CountdownGate()
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 10), .countdown(2))
        XCTAssertFalse(gate.cancelForInteraction(at: 9.99))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 11), .countdown(1))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 12), .submit("A"))
    }

    func testActualInteractionDuringCountdownStillSuppressesCurrentWindow() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 2, now: 10)
        XCTAssertTrue(gate.cancelForInteraction(at: 10.5))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 11), .idle)
    }

    func testStaleInteractionCannotCancelConfirmationButCurrentInputCan() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 2, now: 10)
        XCTAssertEqual(gate.submitNow(), "A")
        XCTAssertFalse(gate.cancelForInteraction(at: 9.9))
        XCTAssertTrue(gate.cancelForInteraction(at: 10.5))
        XCTAssertFalse(gate.cancelForInteraction(at: .nan))
    }

    func testWaitsUntilDeadlineAndSubmitsOnlyOnce() {
        var gate = CountdownGate()
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 10), .countdown(3))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 11), .countdown(2))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 12), .countdown(1))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 13), .submit("A"))
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 3, now: 14), .idle)
    }

    func testCancelSuppressesUntilWindowDisappears() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 2, now: 0)
        gate.cancel()
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 1), .idle)
        _ = gate.observe(target: nil, enabled: true, delay: 2, now: 2)
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 3), .countdown(2))
    }

    func testChangedWindowStartsItsOwnCountdown() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 2, now: 0)
        XCTAssertEqual(gate.observe(target: "B", enabled: true, delay: 2, now: 1), .countdown(2))
        XCTAssertEqual(gate.observe(target: "B", enabled: true, delay: 2, now: 2), .countdown(1))
        XCTAssertEqual(gate.observe(target: "B", enabled: true, delay: 2, now: 3), .submit("B"))
    }

    func testPausePreventsSubmissionAndDoesNotRearmVisibleWindow() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 2, now: 0)
        XCTAssertEqual(gate.observe(target: "A", enabled: false, delay: 2, now: 1), .idle)
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 2), .idle)
    }

    func testLongSchedulingGapCancelsInsteadOfSubmittingAfterWake() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 2, now: 0)
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 100), .idle)
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 101), .idle)
    }

    func testMultipleCancelledWindowsStaySuppressedWhileVisible() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 5, now: 0, visible: ["A", "B"])
        gate.cancel()
        _ = gate.observe(target: "B", enabled: true, delay: 5, now: 1, visible: ["A", "B"])
        gate.cancel()
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 5, now: 2, visible: ["A", "B"]), .idle)
    }

    func testImmediateSubmissionIsConsumedOnlyOnce() {
        var gate = CountdownGate()
        _ = gate.observe(target: "A", enabled: true, delay: 10, now: 0)
        XCTAssertEqual(gate.submitNow(), "A")
        XCTAssertNil(gate.submitNow())
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 10, now: 1), .idle)
    }

    func testInvalidDelayAndReversedTimeNeverSubmit() {
        var gate = CountdownGate()
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 0, now: 1), .idle)
        _ = gate.observe(target: nil, enabled: true, delay: 2, now: 2)
        _ = gate.observe(target: "A", enabled: true, delay: 2, now: 3)
        XCTAssertEqual(gate.observe(target: "A", enabled: true, delay: 2, now: 1), .idle)
    }
}
