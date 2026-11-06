import Foundation

/// Settings visibility is diagnostic context, not a switch for automation.
public struct AutomationConditions: Codable, Equatable {
    public var enabled: Bool
    public var hasCredentials: Bool
    public var accessibilityGranted: Bool
    public var suspended: Bool
    public var settingsVisible: Bool

    public init(enabled: Bool, hasCredentials: Bool, accessibilityGranted: Bool,
                suspended: Bool, settingsVisible: Bool) {
        self.enabled = enabled
        self.hasCredentials = hasCredentials
        self.accessibilityGranted = accessibilityGranted
        self.suspended = suspended
        self.settingsVisible = settingsVisible
    }

    public var isReady: Bool { enabled && hasCredentials && accessibilityGranted && !suspended }
}
