import Foundation

public enum PermissionCategory: String, Codable, CaseIterable {
    case files, localNetwork, camera, microphone, screen, location, contacts, notifications, photos, calendar, bluetooth, automation
    public var label: String {
        switch self {
        case .files: return "文件夹访问"
        case .localNetwork: return "本地网络"
        case .camera: return "相机"
        case .microphone: return "麦克风"
        case .screen: return "屏幕与音频访问"
        case .location: return "定位"
        case .contacts: return "通讯录"
        case .notifications: return "通知"
        case .photos: return "照片"
        case .calendar: return "日历"
        case .bluetooth: return "蓝牙"
        case .automation: return "应用间自动化控制"
        }
    }
}
public struct PermissionFacts {
    public let trustedProvider: Bool
    public let passwordFields: Int
    public let text: String
    public let buttons: [AuthButton]
    public init(trustedProvider: Bool, passwordFields: Int, text: String, buttons: [AuthButton]) {
        self.trustedProvider = trustedProvider; self.passwordFields = passwordFields
        self.text = text; self.buttons = buttons
    }
}
public enum PermissionRejection: String, Codable { case untrusted, password, protectedRequester, unsupported, ambiguous, noAllowButton }
public struct PermissionMatch {
    public let category: PermissionCategory
    public let buttonIndex: Int
}
public struct PermissionDecision {
    public let match: PermissionMatch?
    public let rejection: PermissionRejection?
}
public enum PermissionPolicy {
    private static let resources: [(PermissionCategory, [String])] = [
        (.screen, ["screen", "屏幕", "螢幕", "画面収録", "画面と", "画面への"]),
        (.localNetwork, ["local network", "本地网络", "本機網路", "ローカルネットワーク"]),
        (.camera, ["camera", "相机", "摄像头", "カメラ"]),
        (.microphone, ["microphone", "麦克风", "麥克風", "マイク"]),
        (.location, ["location", "位置", "定位", "位置情報"]),
        (.contacts, ["contacts", "通讯录", "通信录", "連絡先"]),
        (.notifications, ["notifications", "通知"]),
        (.photos, ["photos", "照片", "写真"]),
        (.calendar, ["calendar", "日历", "行事曆", "カレンダー"]),
        (.bluetooth, ["bluetooth", "蓝牙", "藍牙"]),
        (.files, ["files", "documents folder", "downloads folder", "desktop folder", "removable volume", "network volume", "文件", "文件夹", "フォルダ", "ファイル"]),
        (.automation, ["control", "控制", "コントロール", "操作"])
    ]
    private static let forbidden = ["codex", "chatgpt", "claude", "macauthassistant", "mac 授权助手",
        "keychain", "钥匙串", "鑰匙圈", "キーチェーン", "1password", "apple account", "apple id",
        "delete ", "erase ", "remove ", "删除", "抹掉", "格式化", "削除", "消去", "payment", "purchase", "付款", "购买", "購入",
        "malicious", "malware", "unidentified developer", "cannot verify", "恶意", "无法验证", "開発元を検証"]
    private static let rankedLabels: [[String]] = [
        ["allow once", "允许一次", "仅允许一次", "今回のみ許可"],
        ["allow while using app", "allow while using the app", "使用app期间允许", "使用应用期间允许", "アプリの使用中は許可"],
        ["allow", "允许", "允許", "許可"], ["always allow", "始终允许", "总是允许", "常に許可"],
        ["ok", "好", "确定", "確定"]
    ]
    public static func decide(_ facts: PermissionFacts) -> PermissionDecision {
        func refuse(_ reason: PermissionRejection) -> PermissionDecision { PermissionDecision(match: nil, rejection: reason) }
        guard facts.trustedProvider else { return refuse(.untrusted) }
        guard facts.passwordFields == 0 else { return refuse(.password) }
        let text = facts.text.lowercased()
        guard !forbidden.contains(where: { text.contains($0) }) else { return refuse(.protectedRequester) }
        let requests = ["would like", "wants to", "wants access", "requesting", "allow ", "continue to allow", "can access", "想要", "想给", "想向", "想使用", "请求", "允許", "允许", "許可", "求めています", "アクセス", "使用しよう"]
        var resourceText = text
        let starts = ["would like", "wants to", "wants access", "requesting", "can access", "想要", "想给", "想向", "想使用", "请求", "が"]
            .compactMap { text.range(of: $0)?.lowerBound }
        if let start = starts.min() { resourceText = String(text[start...]) }
        func containsResource(_ word: String) -> Bool {
            if word.unicodeScalars.allSatisfy({ CharacterSet.lowercaseLetters.contains($0) && $0.isASCII }) {
                return resourceText.range(of: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b", options: .regularExpression) != nil
            }
            return resourceText.contains(word)
        }
        guard requests.contains(where: { text.contains($0) }),
              let category = resources.first(where: { $0.1.contains(where: containsResource) })?.0 else { return refuse(.unsupported) }
        let negative = ["don't allow", "don’t allow", "deny", "cancel", "不允许", "拒绝", "取消", "許可しない", "キャンセル"]
        var candidates: [(Int, Int)] = []
        for (index, button) in facts.buttons.enumerated() where button.supportsPress && !button.isCancel {
            let labels = button.labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard !labels.contains(where: { negative.contains($0) }) else { continue }
            if let rank = rankedLabels.firstIndex(where: { choices in labels.contains(where: { choices.contains($0) }) }) {
                candidates.append((index, rank))
            }
        }
        guard let best = candidates.map(\.1).min() else { return refuse(.noAllowButton) }
        let selected = candidates.filter { $0.1 == best }
        guard selected.count == 1 else { return refuse(.ambiguous) }
        return PermissionDecision(match: PermissionMatch(category: category, buttonIndex: selected[0].0), rejection: nil)
    }

    public static func chooseWindow(eligible: [String], current: String?) -> String? {
        if let current, eligible.contains(current) { return current }
        return eligible.first
    }
}
