import XCTest
@testable import AuthCore

final class ValidationEvidenceTests: XCTestCase {
    func testOSSuccessWithoutAnObservedDialogDoesNotPass() {
        var evidence = ValidationEvidence()
        evidence.finish(status: 0)
        XCTAssertEqual(evidence.result, .notExercised)
    }

    func testOnlyTheCompleteOrderedAutomaticPathAndOSSuccessPass() {
        var evidence = ValidationEvidence()
        for stage in [ValidationStage.dialogSeen, .countdown, .passwordWritten, .confirmationSent] {
            evidence.record(stage)
        }
        evidence.finish(status: 0)
        XCTAssertEqual(evidence.result, .passed)
    }

    func testManualInteractionOrWrongOrderNeverCountsAsAutomaticSuccess() {
        var interrupted = ValidationEvidence()
        for stage in [ValidationStage.dialogSeen, .countdown, .manualInteraction, .passwordWritten, .confirmationSent] {
            interrupted.record(stage)
        }
        interrupted.finish(status: 0)
        XCTAssertEqual(interrupted.result, .interrupted)
        var wrongOrder = ValidationEvidence()
        for stage in [ValidationStage.dialogSeen, .confirmationSent, .countdown, .passwordWritten] {
            wrongOrder.record(stage)
        }
        wrongOrder.finish(status: 0)
        XCTAssertEqual(wrongOrder.result, .incomplete)
    }

    func testOSRejectionFailsEvenAfterAllAutomaticStages() {
        var evidence = ValidationEvidence()
        for stage in [ValidationStage.dialogSeen, .countdown, .passwordWritten, .confirmationSent] { evidence.record(stage) }
        evidence.finish(status: -60005)
        XCTAssertEqual(evidence.result, .failed)
    }
}
