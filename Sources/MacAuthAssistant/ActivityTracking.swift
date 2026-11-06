import Foundation
import AuthCore

extension DetectedDialog {
    var activityToken: String { "administrator:" + id }
    var activityRequest: ActivityRequest { ActivityRequest(kind: .administrator, context: context) }
}
extension PermissionWindow {
    var activityToken: String { "permission:" + id }
    var activityRequest: ActivityRequest { ActivityRequest(kind: .permission, context: context, category: category) }
}
extension AppState {
    func trackAdministrator(_ dialogs: [DetectedDialog]) {
        activity.reconcile(kind: .administrator, visible: Set(dialogs.map(\.activityToken)))
        for dialog in dialogs {
            let request = dialog.activityRequest
            let reason = rejection(for: dialog)
            activity.observe(token: dialog.activityToken, request: request,
                             retryIgnored: enabled && reason == nil && scanner.isFocused(dialog) && !gate.isSuppressed(dialog.id))
            if activity.checkBlocked(token: dialog.activityToken, request: request, text: dialog.context) { continue }
            if !enabled { activity.finish(token: dialog.activityToken, outcome: .ignored, reason: "管理员自动处理已暂停") }
            else if let reason { activity.finish(token: dialog.activityToken, outcome: .ignored, reason: reason) }
        }
    }
    func administratorBlocked(_ dialog: DetectedDialog) -> Bool {
        activity.checkBlocked(token: dialog.activityToken, request: dialog.activityRequest, text: dialog.context)
    }
}
