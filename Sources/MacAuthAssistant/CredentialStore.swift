import Foundation
import Security
import LocalAuthentication
import AuthCore

struct CredentialStore {
    private static let accessLock = NSRecursiveLock()
    private let identity: [String: Any]

    init(service: String = "local.mac-auth-assistant.credentials") {
        identity = [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service, kSecAttrAccount as String: "administrator"]
    }

    func load(allowInteraction: Bool = false) throws -> Credentials? {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        // LAContext only controls the data-protection path. Existing credentials
        // live in the macOS login keychain, whose CSSM path can otherwise show UI.
        var previousInteraction: Bool?
        if !allowInteraction {
            var allowed: DarwinBoolean = false
            let readStatus = SecKeychainGetUserInteractionAllowed(&allowed)
            guard readStatus == errSecSuccess else { throw StoreError(status: readStatus) }
            let setStatus = SecKeychainSetUserInteractionAllowed(false)
            guard setStatus == errSecSuccess else { throw StoreError(status: setStatus) }
            previousInteraction = allowed.boolValue
        }
        defer {
            if let previousInteraction { SecKeychainSetUserInteractionAllowed(previousInteraction) }
        }
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Never create another authorization prompt from the automation polling loop.
        let authentication = LAContext()
        authentication.interactionNotAllowed = !allowInteraction
        query[kSecUseAuthenticationContext as String] = authentication
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreError(status: status) }
        let decoded = try JSONDecoder().decode(Credentials.self, from: data)
        return try Credentials(account: decoded.account, password: decoded.password)
    }

    func save(_ credentials: Credentials) throws {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        let data = try JSONEncoder().encode(credentials)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(identity as CFDictionary, update)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Mac 授权助手 — 管理员凭据"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw StoreError(status: added) }
        } else if status != errSecSuccess { throw StoreError(status: status) }
    }

    func delete() throws {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError(status: status) }
    }

    struct StoreError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                return "已保存凭据需要重新允许访问，请点击“读取已保存凭据”并按系统提示确认。"
            }
            if status == errSecUserCanceled { return "已取消钥匙串授权，自动处理仍暂停。" }
            return "钥匙串操作失败（\(status)），自动处理已暂停。请检查钥匙串是否解锁。"
        }
    }
}
