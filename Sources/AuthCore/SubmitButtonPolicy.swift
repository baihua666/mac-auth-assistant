import Foundation

public struct AuthButton {
    public let labels: [String]
    public let supportsPress: Bool
    public let isDefault: Bool
    public let isCancel: Bool

    public init(labels: [String], supportsPress: Bool, isDefault: Bool = false, isCancel: Bool = false) {
        self.labels = labels
        self.supportsPress = supportsPress
        self.isDefault = isDefault
        self.isCancel = isCancel
    }
}

public enum SubmitButtonPolicy {
    private static let positive: Set<String> = ["好", "确定", "允许", "解锁", "安装", "继续", "ok", "allow", "unlock",
        "install", "continue", "authenticate", "許可", "認証", "続ける", "ロックを解除"]
    private static let negative: Set<String> = ["取消", "拒绝", "不允许", "cancel", "deny", "don't allow", "キャンセル", "許可しない"]

    public static func index(in buttons: [AuthButton]) -> Int? {
        func normalized(_ button: AuthButton) -> Set<String> {
            Set(button.labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        }
        let cancel = Set(buttons.indices.filter { buttons[$0].isCancel || !normalized(buttons[$0]).isDisjoint(with: negative) })
        let candidates = buttons.indices.filter { buttons[$0].supportsPress && !cancel.contains($0) }
        let defaults = candidates.filter { buttons[$0].isDefault }
        if defaults.count == 1 { return defaults[0] }
        let labelled = candidates.filter { !normalized(buttons[$0]).isDisjoint(with: positive) }
        if labelled.count == 1 { return labelled[0] }
        if buttons.count == 2, cancel.count == 1, candidates.count == 1 { return candidates[0] }
        return nil
    }
}
