import AppKit
import ApplicationServices
import AuthCore

struct DetectedDialog {
    let id: String
    let pid: pid_t
    let window: AXUIElement
    let password: AXUIElement?
    let account: AXUIElement?
    let accountValue: String
    let submitElement: AXUIElement?
    let submitAction: String
    let context: String
    let facts: DialogFacts
    let isNewWindow: Bool

    var rejection: String? { DialogPolicy.rejection(for: facts) }

    func isSameForm(as other: DetectedDialog) -> Bool {
        guard id == other.id, pid == other.pid, context == other.context,
              accountValue == other.accountValue, CFEqual(window, other.window),
              let password, let otherPassword = other.password,
              CFEqual(password, otherPassword), submitAction == other.submitAction,
              let submitElement, let otherSubmit = other.submitElement else { return false }
        return CFEqual(submitElement, otherSubmit)
    }
}

@MainActor
final class DialogScanner {
    private var previous: [DetectedDialog] = []
    private(set) var current: [DetectedDialog] = []
    private(set) var providerCount = 0
    private(set) var trustedProviderCount = 0

    func scan() -> [DetectedDialog] {
        providerCount = 0
        trustedProviderCount = 0
        guard AXIsProcessTrusted() else { current = []; return [] }
        var result: [DetectedDialog] = []
        for app in NSWorkspace.shared.runningApplications where SystemAuthenticationProvider.identifiers.contains(app.bundleIdentifier ?? "") {
            providerCount += 1
            guard SystemAuthenticationProvider.isTrusted(app) else { continue }
            trustedProviderCount += 1
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            let windows = AX.value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            for window in windows {
                let old = previous.first { $0.pid == app.processIdentifier && CFEqual($0.window, window) }
                result.append(inspect(window, pid: app.processIdentifier, id: old?.id ?? UUID().uuidString,
                                      isNew: old == nil))
            }
        }
        previous = result
        current = result
        return result
    }

    func inspect(_ window: AXUIElement, pid: pid_t, id: String, isNew: Bool = false) -> DetectedDialog {
        let nodes = AX.descendants(window)
        let passwordFields = nodes.filter { AX.string($0, kAXSubroleAttribute) == kAXSecureTextFieldSubrole }
        let accountFields = nodes.filter {
            AX.string($0, kAXRoleAttribute) == kAXTextFieldRole && AX.string($0, kAXSubroleAttribute) != kAXSecureTextFieldSubrole
        }
        let context = AX.staticContext(nodes)
        let password = passwordFields.first
        let account = accountFields.first
        let defaultButton = AX.element(window, kAXDefaultButtonAttribute)
        let cancelButton = AX.element(window, kAXCancelButtonAttribute)
        var buttons = AX.dialogButtons(nodes)
        if let defaultButton, AX.string(defaultButton, kAXRoleAttribute) == kAXButtonRole,
           !buttons.contains(where: { CFEqual($0, defaultButton) }) { buttons.append(defaultButton) }
        let descriptors = buttons.map { button in
            let identifier = AX.string(button, kAXIdentifierAttribute).lowercased()
            return AuthButton(labels: AX.buttonLabels(button), supportsPress: AX.actions(button).contains(kAXPressAction),
                              isDefault: defaultButton.map { CFEqual(button, $0) } ?? false,
                              isCancel: (cancelButton.map { CFEqual(button, $0) } ?? false) ||
                                ["cancel", "cancelbutton", "cancel-button"].contains(identifier))
        }
        let submit = SubmitButtonPolicy.index(in: descriptors).map { buttons[$0] }
        let action = kAXPressAction
        let canSubmit = submit.map { AX.actions($0).contains(action) } ?? false
        let facts = DialogFacts(trustedProvider: true, passwordFields: passwordFields.count,
                                accountFields: accountFields.count,
                                canWritePassword: password.map { AX.settable($0, kAXValueAttribute) } ?? false,
                                canSubmit: canSubmit, passwordState: password.map { AX.inputState($0) } ?? .unknown,
                                context: context)
        return DetectedDialog(id: id, pid: pid, window: window, password: password, account: account,
                              accountValue: account.map { AX.string($0, kAXValueAttribute) } ?? "",
                              submitElement: submit, submitAction: action, context: context, facts: facts, isNewWindow: isNew)
    }

    func isFocused(_ dialog: DetectedDialog) -> Bool {
        guard AX.focusedPID == dialog.pid,
              let window = AX.element(AXUIElementCreateApplication(dialog.pid), kAXFocusedWindowAttribute) else { return false }
        return CFEqual(window, dialog.window)
    }
}
