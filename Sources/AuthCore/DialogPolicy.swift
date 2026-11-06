import Foundation

public enum PasswordInputState: String, Codable { case empty, nonempty, unknown }

public struct DialogFacts {
    public let trustedProvider: Bool
    public let passwordFields: Int
    public let accountFields: Int
    public let canWritePassword: Bool
    public let canSubmit: Bool
    public let passwordState: PasswordInputState
    public var passwordIsEmpty: Bool { passwordState == .empty }
    public let context: String

    public init(trustedProvider: Bool, passwordFields: Int, accountFields: Int,
                canWritePassword: Bool, canSubmit: Bool, passwordIsEmpty: Bool, context: String = "") {
        self.init(trustedProvider: trustedProvider, passwordFields: passwordFields, accountFields: accountFields,
                  canWritePassword: canWritePassword, canSubmit: canSubmit,
                  passwordState: passwordIsEmpty ? .empty : .nonempty, context: context)
    }

    public init(trustedProvider: Bool, passwordFields: Int, accountFields: Int,
                canWritePassword: Bool, canSubmit: Bool, passwordState: PasswordInputState, context: String = "") {
        self.trustedProvider = trustedProvider
        self.passwordFields = passwordFields
        self.accountFields = accountFields
        self.canWritePassword = canWritePassword
        self.canSubmit = canSubmit
        self.passwordState = passwordState
        self.context = context
    }
}

public enum DialogPolicy {
    public static func rejection(for facts: DialogFacts, allowUnreadableInput: Bool = false) -> String? {
        guard facts.trustedProvider else { return "无法确认窗口属于系统认证服务" }
        guard facts.passwordFields == 1, facts.accountFields <= 1 else { return "窗口不是单一密码验证表单" }
        let otherCredentials = ["apple account", "apple id", "icloud", "keychain", "钥匙串", "鑰匙圈", "キーチェーン",
                                "disk password", "磁盘密码", "磁碟密碼", "ディスクのパスワード",
                                "network password", "网络密码", "網路密碼", "ネットワークパスワード"]
        if otherCredentials.contains(where: { facts.context.localizedCaseInsensitiveContains($0) }) {
            return "此窗口可能需要独立凭据，请手动处理"
        }
        guard facts.canWritePassword else { return "系统没有开放此密码框的填写接口" }
        guard facts.canSubmit else { return "系统没有开放此窗口的确认接口" }
        if facts.passwordState == .nonempty { return "检测到已有输入，本次交由手动处理" }
        if facts.passwordState == .unknown && !allowUnreadableInput {
            return "系统隐藏了既有密码框状态，请重新触发一个新授权弹窗"
        }
        return nil
    }
}
