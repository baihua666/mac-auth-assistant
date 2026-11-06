import Foundation

public struct Credentials: Codable {
    public let account: String
    public let password: String

    public init(account: String, password: String) throws {
        let account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !password.isEmpty,
              !account.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !password.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CredentialError.invalid
        }
        self.account = account
        self.password = password
    }

    public enum CredentialError: LocalizedError {
        case invalid
        public var errorDescription: String? { "请输入管理员账号和密码，不能包含换行或控制字符。" }
    }
}
