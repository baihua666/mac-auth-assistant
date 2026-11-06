import XCTest
import CoreGraphics
@testable import MacAuthAssistant

final class PasswordKeyboardEventsTests: XCTestCase {
    func testGeneratedEventsPreserveSpacesUnicodeAndLongPasswordWithoutPosting() throws {
        let fixture = "  fixture🔐日本語 " + String(repeating: "a", count: 30) + " 🗝️ "
        let events = try XCTUnwrap(PasswordKeyboardEvents.make(for: fixture))
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events.count % 2, 0)
        var received: [UniChar] = []
        for (index, event) in events.enumerated() {
            XCTAssertEqual(event.type, index % 2 == 0 ? .keyDown : .keyUp)
            XCTAssertTrue(PasswordKeyboardEvents.isOwn(event))
            if index % 2 == 0 {
                var buffer = [UniChar](repeating: 0, count: 32)
                var count = 0
                event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &count,
                                               unicodeString: &buffer)
                XCTAssertLessThanOrEqual(count, 20)
                XCTAssertFalse((0xD800...0xDBFF).contains(buffer[count - 1]))
                received += buffer.prefix(count)
            }
        }
        XCTAssertEqual(String(decoding: received, as: UTF16.self), fixture)
    }

    func testUnmarkedHumanEventsAreNotTreatedAsOurPasswordInput() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertFalse(PasswordKeyboardEvents.isOwn(event))
        XCTAssertFalse(PasswordKeyboardEvents.isOwn(nil))
        let mouse = try XCTUnwrap(CGEvent(mouseEventSource: CGEventSource(stateID: .privateState),
                                         mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left))
        PasswordKeyboardEvents.markAsOwn(mouse)
        XCTAssertTrue(PasswordKeyboardEvents.isOwn(mouse))
        XCTAssertNil(PasswordKeyboardEvents.make(for: ""))
        XCTAssertNil(PasswordKeyboardEvents.make(for: "fixture\n"))
        XCTAssertNil(PasswordKeyboardEvents.make(for: "fixture\t"))
    }
}
