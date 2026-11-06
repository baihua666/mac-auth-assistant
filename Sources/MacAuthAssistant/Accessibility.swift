import AppKit
import ApplicationServices
import Security
import AuthCore

typealias InputState = PasswordInputState

enum AX {
    static func dialogButtons(_ nodes: [AXUIElement]) -> [AXUIElement] {
        let titlebar = [kAXCloseButtonSubrole, kAXMinimizeButtonSubrole, kAXZoomButtonSubrole, kAXFullScreenButtonSubrole]
        return nodes.filter { string($0, kAXRoleAttribute) == kAXButtonRole && !titlebar.contains(string($0, kAXSubroleAttribute)) }
    }

    static func staticContext(_ nodes: [AXUIElement]) -> String {
        nodes.filter { [kAXStaticTextRole, kAXWindowRole].contains(string($0, kAXRoleAttribute)) }.map {
            (string($0, kAXRoleAttribute) == kAXStaticTextRole ? string($0, kAXValueAttribute) : "") +
                string($0, kAXDescriptionAttribute) + string($0, kAXTitleAttribute)
        }.joined(separator: "\n")
    }
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    static func element(_ node: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(node, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    static func string(_ node: AXUIElement, _ attribute: String) -> String {
        value(node, attribute) as? String ?? ""
    }

    static func bool(_ node: AXUIElement, _ attribute: String) -> Bool {
        (value(node, attribute) as? NSNumber)?.boolValue ?? false
    }

    static func settable(_ node: AXUIElement, _ attribute: String) -> Bool {
        var result: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(node, attribute as CFString, &result) == .success && result.boolValue
    }

    static func actions(_ node: AXUIElement) -> [String] {
        var result: CFArray?
        guard AXUIElementCopyActionNames(node, &result) == .success else { return [] }
        return result as? [String] ?? []
    }

    static func buttonLabels(_ button: AXUIElement) -> [String] {
        let attributes = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXValueDescriptionAttribute, kAXHelpAttribute]
        var labels = attributes.map { string(button, $0) }.filter { !$0.isEmpty }
        var textNodes = descendants(button).filter { string($0, kAXRoleAttribute) == kAXStaticTextRole }
        if let title = element(button, kAXTitleUIElementAttribute) { textNodes.append(title) }
        textNodes += value(button, kAXLabelUIElementsAttribute) as? [AXUIElement] ?? []
        for node in textNodes where string(node, kAXSubroleAttribute) != kAXSecureTextFieldSubrole {
            labels += [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].map { string(node, $0) }.filter { !$0.isEmpty }
        }
        return labels
    }

    static func descendants(_ root: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        func visit(_ node: AXUIElement, depth: Int) {
            guard depth < 12, found.count < 200 else { return }
            if string(node, kAXRoleAttribute) == kAXMenuBarRole { return }
            found.append(node)
            for child in value(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return found
    }

    static func inputState(_ node: AXUIElement) -> InputState {
        if let length = value(node, kAXNumberOfCharactersAttribute) as? NSNumber, length.intValue >= 0 {
            return length.intValue > 0 ? .nonempty : .empty
        }
        // Inspect emptiness only; never retain or log password-field contents.
        if let text = value(node, kAXValueAttribute) as? String { return text.isEmpty ? .empty : .nonempty }
        if let text = value(node, kAXValueAttribute) as? NSAttributedString { return text.length == 0 ? .empty : .nonempty }
        if let rawRange = value(node, kAXVisibleCharacterRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() {
            let rangeValue = rawRange as! AXValue
            var range = CFRange()
            if AXValueGetType(rangeValue) == .cfRange, AXValueGetValue(rangeValue, .cfRange, &range),
               range.location >= 0, range.length >= 0 {
                return range.location > 0 || range.length > 0 ? .nonempty : .empty
            }
        }
        return .unknown
    }

    static var focusedPID: pid_t? {
        guard let application = element(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(application, &pid) == .success else { return nil }
        return pid
    }
}

enum SystemAuthenticationProvider {
    static let identifiers: Set<String> = [
        "com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent",
        "com.apple.SecurityAgentHelper.arm64", "com.apple.SecurityAgentHelper.x86_64"
    ]

    static func isTrusted(_ app: NSRunningApplication, identifiers: Set<String> = SystemAuthenticationProvider.identifiers) -> Bool {
        guard let id = app.bundleIdentifier, identifiers.contains(id),
              app.bundleURL?.path.hasPrefix("/System/Library/") == true else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: app.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
