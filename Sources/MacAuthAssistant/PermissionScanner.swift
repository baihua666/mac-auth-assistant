import AppKit
import ApplicationServices
import AuthCore

struct PermissionWindow {
    let id: String
    let pid: pid_t
    let window: AXUIElement
    let context: String
    let decision: PermissionDecision
    let button: AXUIElement?
    var category: PermissionCategory? { decision.match?.category }
    func matches(_ other: PermissionWindow) -> Bool {
        guard id == other.id, pid == other.pid, context == other.context, category == other.category,
              CFEqual(window, other.window), let button, let otherButton = other.button else { return false }
        return CFEqual(button, otherButton)
    }
}

@MainActor
protocol PermissionScanning {
    var providerCount: Int { get }
    var trustedProviderCount: Int { get }
    var windowReadCodes: [Int32] { get }
    func scan() -> [PermissionWindow]
}

@MainActor
final class PermissionScanner: PermissionScanning {
    static let providers: Set<String> = ["com.apple.UserNotificationCenter"]
    private var previous: [PermissionWindow] = []
    private(set) var providerCount = 0
    private(set) var trustedProviderCount = 0
    private(set) var windowReadCodes: [Int32] = []
    func scan() -> [PermissionWindow] {
        providerCount = 0; trustedProviderCount = 0; windowReadCodes = []
        guard AXIsProcessTrusted() else { return [] }
        var found: [PermissionWindow] = []
        for app in NSWorkspace.shared.runningApplications where Self.providers.contains(app.bundleIdentifier ?? "") {
            providerCount += 1
            guard SystemAuthenticationProvider.isTrusted(app, identifiers: Self.providers) else { continue }
            trustedProviderCount += 1
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            var rawWindows: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &rawWindows)
            windowReadCodes.append(read.rawValue)
            for window in rawWindows as? [AXUIElement] ?? [] {
                let nodes = AX.descendants(window)
                let buttons = AX.dialogButtons(nodes)
                let buttonNodes = buttons.flatMap { AX.descendants($0) }
                let context = AX.staticContext(nodes.filter { node in !buttonNodes.contains { CFEqual($0, node) } })
                let descriptor = buttons.map { AuthButton(labels: AX.buttonLabels($0), supportsPress: AX.actions($0).contains(kAXPressAction)) }
                let facts = PermissionFacts(trustedProvider: !nodes.contains {
                    ["AXWebArea", kAXTextFieldRole, kAXComboBoxRole].contains(AX.string($0, kAXRoleAttribute))
                },
                                            passwordFields: nodes.filter { AX.string($0, kAXSubroleAttribute) == kAXSecureTextFieldSubrole }.count,
                                            text: context, buttons: descriptor)
                let decision = PermissionPolicy.decide(facts)
                let id = previous.first { $0.pid == app.processIdentifier && CFEqual($0.window, window) }?.id ?? UUID().uuidString
                found.append(PermissionWindow(id: id, pid: app.processIdentifier, window: window, context: context,
                                              decision: decision, button: decision.match.map { buttons[$0.buttonIndex] }))
            }
        }
        previous = found
        return found
    }
}
