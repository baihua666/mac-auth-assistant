import CoreGraphics
import Foundation

enum PasswordKeyboardEvents {
    private static let marker: Int64 = 0x4D414341555448

    /// Creates events only. Posting is restricted to the revalidated system PID by Submission.
    static func make(for password: String) -> [CGEvent]? {
        guard !password.isEmpty,
              !password.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let source = CGEventSource(stateID: .privateState) else { return nil }
        let units = Array(password.utf16)
        var events: [CGEvent] = []
        var start = 0
        while start < units.count {
            var end = min(start + 20, units.count)
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
            let chunk = Array(units[start..<end])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { return nil }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                markAsOwn(event)
                events.append(event)
            }
            start = end
        }
        return events
    }

    static func isOwn(_ event: CGEvent?) -> Bool {
        guard let event else { return false }
        return event.getIntegerValueField(.eventSourceUserData) == marker &&
            event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier)
    }

    static func markAsOwn(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }
}
