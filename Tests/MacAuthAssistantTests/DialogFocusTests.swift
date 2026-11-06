import XCTest
import CoreGraphics
@testable import MacAuthAssistant

final class DialogFocusTests: XCTestCase {
    func testClickOnlyTargetsVisiblePasswordFieldOfExactSystemWindow() {
        let window = CGRect(x: 100, y: 100, width: 500, height: 500)
        let field = CGRect(x: 130, y: 300, width: 400, height: 40)
        XCTAssertEqual(DialogFocusController.clickPoint(field: field, window: window, topWindow: window,
                                                       expectedPID: 42, topPID: 42), CGPoint(x: 330, y: 320))
        XCTAssertNil(DialogFocusController.clickPoint(field: field, window: window, topWindow: window,
                                                     expectedPID: 42, topPID: 43))
        XCTAssertNil(DialogFocusController.clickPoint(field: field, window: window,
                                                     topWindow: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                                                     expectedPID: 42, topPID: 42))
        XCTAssertNil(DialogFocusController.clickPoint(field: CGRect(x: 0, y: 0, width: 20, height: 20),
                                                     window: window, topWindow: window, expectedPID: 42, topPID: 42))
        XCTAssertNil(DialogFocusController.clickPoint(field: .zero, window: window, topWindow: window,
                                                     expectedPID: 42, topPID: 42))
    }
}
