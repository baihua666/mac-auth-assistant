import AppKit
import ApplicationServices

enum DialogFocusResult: String, Codable { case requested, focused, occluded, unavailable, failed }

@MainActor
final class DialogFocusController {
    func request(_ dialog: DetectedDialog) -> DialogFocusResult {
        guard let app = NSRunningApplication(processIdentifier: dialog.pid),
              SystemAuthenticationProvider.isTrusted(app), let password = dialog.password else { return .unavailable }
        _ = app.activate(options: [.activateIgnoringOtherApps])
        _ = AXUIElementPerformAction(dialog.window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(dialog.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(password, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard let field = Self.bounds(password), let window = Self.bounds(dialog.window) else { return .unavailable }
        let point = CGPoint(x: field.midX, y: field.midY)
        guard let top = Self.topWindow(at: point),
              let point = Self.clickPoint(field: field, window: window, topWindow: top.bounds,
                                          expectedPID: dialog.pid, topPID: top.pid),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else { return .occluded }
        PasswordKeyboardEvents.markAsOwn(down)
        PasswordKeyboardEvents.markAsOwn(up)
        // Only a non-secret focus click uses the global stream. Password events remain PID-directed.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .requested // The next tick must independently verify focus; API success is insufficient.
    }

    nonisolated static func clickPoint(field: CGRect, window: CGRect, topWindow: CGRect,
                           expectedPID: pid_t, topPID: pid_t) -> CGPoint? {
        let values = [field.minX, field.minY, field.width, field.height,
                      window.minX, window.minY, window.width, window.height]
        guard values.allSatisfy({ $0.isFinite }), field.width > 1, field.height > 1,
              expectedPID > 0, topPID == expectedPID, window.contains(field),
              abs(window.minX - topWindow.minX) < 3, abs(window.minY - topWindow.minY) < 3,
              abs(window.width - topWindow.width) < 3, abs(window.height - topWindow.height) < 3 else { return nil }
        return CGPoint(x: field.midX, y: field.midY)
    }

    static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let rawPosition = AX.value(element, kAXPositionAttribute),
              let rawSize = AX.value(element, kAXSizeAttribute),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func topWindow(at point: CGPoint) -> (pid: pid_t, bounds: CGRect)? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in windows {
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary), bounds.contains(point) else { continue }
            return (pid, bounds)
        }
        return nil
    }
}
