import XCTest
@testable import AuthCore

final class SubmitButtonPolicyTests: XCTestCase {
    func testSelectsARealButtonUsingAnyExposedCaption() {
        let buttons = [AuthButton(labels: ["", "好"], supportsPress: true),
                       AuthButton(labels: ["取消"], supportsPress: true)]
        XCTAssertEqual(SubmitButtonPolicy.index(in: buttons), 0)
    }

    func testUsesSystemCancelIdentityWhenCaptionsAreNotExposed() {
        let buttons = [AuthButton(labels: [], supportsPress: true, isCancel: true),
                       AuthButton(labels: [], supportsPress: true)]
        XCTAssertEqual(SubmitButtonPolicy.index(in: buttons), 1)
    }

    func testRejectsAnEditingConfirmActionAndAmbiguousButtons() {
        XCTAssertNil(SubmitButtonPolicy.index(in: [AuthButton(labels: ["好"], supportsPress: false)]))
        XCTAssertNil(SubmitButtonPolicy.index(in: [AuthButton(labels: ["允许"], supportsPress: true),
                                                  AuthButton(labels: ["继续"], supportsPress: true)]))
    }
}
