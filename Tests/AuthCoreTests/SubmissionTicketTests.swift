import XCTest
@testable import AuthCore

final class SubmissionTicketTests: XCTestCase {
    func testConfirmationExpiresAfterMainThreadStalls() {
        let ticket = SubmissionTicket(generation: 1, now: 10)
        XCTAssertTrue(ticket.isValid(now: 10.25, generation: 1))
        XCTAssertFalse(ticket.isValid(now: 40, generation: 1))
    }

    func testCancellationAndReversedTimeInvalidatePendingConfirmation() {
        let ticket = SubmissionTicket(generation: 1, now: 10)
        XCTAssertFalse(ticket.isValid(now: 10.25, generation: 2))
        XCTAssertFalse(ticket.isValid(now: 9, generation: 1))
        XCTAssertFalse(ticket.isValid(now: .infinity, generation: 1))
    }
}
