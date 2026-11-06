import Foundation
import Combine
import ServiceManagement

enum LoginItemState: String, Codable {
    case disabled, enabled, requiresApproval, unavailable
    var label: String {
        switch self {
        case .disabled: return "未开启登录后自动启动"
        case .enabled: return "已开启登录后自动启动"
        case .requiresApproval: return "等待在系统登录项中允许"
        case .unavailable: return "系统未找到此应用的登录项"
        }
    }
}

@MainActor
protocol LoginItemService {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct SystemLoginItemService: LoginItemService {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var errorMessage: String?
    private(set) var errorCode: Int?
    private let preferences: UserDefaults
    private let service: LoginItemService
    var isEnabled: Bool { state == .enabled }
    var isRequested: Bool { isEnabled || state == .requiresApproval }

    init(preferences: UserDefaults = .standard, service: LoginItemService? = nil) {
        self.preferences = preferences
        self.service = service ?? SystemLoginItemService()
        state = self.service.state
    }

    func configureOnLaunch() {
        refresh()
        guard !preferences.bool(forKey: "loginItemRegistrationAttempted") else { return }
        // This version enables login startup once; subsequent launches respect system changes.
        setEnabled(true)
    }

    func setEnabled(_ value: Bool) {
        preferences.set(true, forKey: "loginItemRegistrationAttempted")
        errorMessage = nil
        errorCode = nil
        do {
            if value {
                if service.state != .enabled && service.state != .requiresApproval { try service.register() }
            } else if service.state != .disabled { try service.unregister() }
        } catch {
            errorCode = (error as NSError).code
            errorMessage = "登录项设置失败：\(error.localizedDescription)"
        }
        refresh()
    }

    func refresh() { state = service.state }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
