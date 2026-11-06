import XCTest
import Security
import AuthCore
@testable import MacAuthAssistant

final class KeychainInteractionTests: XCTestCase {
    func testBackgroundLoadRestoresTheCallersInteractionSetting() throws {
        var original: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&original), errSecSuccess)
        defer { SecKeychainSetUserInteractionAllowed(original.boolValue) }
        let store = CredentialStore(service: "local.mac-auth-assistant.tests.\(UUID().uuidString)")
        defer { try? store.delete() }
        try store.save(Credentials(account: "fixture", password: "fixture-value"))
        for value in [true, false] {
            XCTAssertEqual(SecKeychainSetUserInteractionAllowed(value), errSecSuccess)
            XCTAssertEqual(try store.load()?.account, "fixture")
            var after: DarwinBoolean = false
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&after), errSecSuccess)
            XCTAssertEqual(after.boolValue, value)
        }
    }

    func testBackgroundLoadDoesNotPromptForAnUntrustedLegacyItem() throws {
        let service = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let store = CredentialStore(service: service)
        defer { try? store.delete() }
        var trusted: SecTrustedApplication?
        XCTAssertEqual(SecTrustedApplicationCreateFromPath("/usr/bin/true", &trusted), errSecSuccess)
        var access: SecAccess?
        XCTAssertEqual(SecAccessCreate("Isolated interaction fixture" as CFString,
                                      [try XCTUnwrap(trusted)] as CFArray, &access), errSecSuccess)
        let data = try JSONEncoder().encode(Credentials(account: "fixture", password: "fixture-value"))
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecAttrAccount as String: "administrator",
                                  kSecAttrAccess as String: try XCTUnwrap(access),
                                  kSecValueData as String: data]
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        let began = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try store.load()) { error in
            // The legacy CSSM path reports authFailed; newer paths can return interactionNotAllowed.
            let status = (error as? CredentialStore.StoreError)?.status
            XCTAssertTrue(status == errSecAuthFailed || status == errSecInteractionNotAllowed)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 2)
    }
}
