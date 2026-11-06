import XCTest
@testable import AuthCore

final class PolicyTests: XCTestCase {
    func testOpaquePasswordStateIsAllowedOnlyForANewWindowObservedWhileArmed() {
        let facts = DialogFacts(trustedProvider: true, passwordFields: 1, accountFields: 1,
                                canWritePassword: true, canSubmit: true, passwordState: .unknown)
        XCTAssertNotNil(DialogPolicy.rejection(for: facts))
        XCTAssertNil(DialogPolicy.rejection(for: facts, allowUnreadableInput: true))
    }

    func testFreshWindowAllowanceDoesNotOverrideKnownInputOrSystemIdentity() {
        let populated = DialogFacts(trustedProvider: true, passwordFields: 1, accountFields: 1,
                                    canWritePassword: true, canSubmit: true, passwordState: .nonempty)
        XCTAssertNotNil(DialogPolicy.rejection(for: populated, allowUnreadableInput: true))
        let untrusted = DialogFacts(trustedProvider: false, passwordFields: 1, accountFields: 1,
                                    canWritePassword: true, canSubmit: true, passwordState: .unknown)
        XCTAssertNotNil(DialogPolicy.rejection(for: untrusted, allowUnreadableInput: true))
    }

    func testGenericSystemAuthenticationIsIndependentOfRequestingApp() {
        for text in ["Used by vphone-launchpad to run its privileged helper as root.",
                     "Installer wants to install software.", "系统设置正在尝试解锁设置。", "認証するにはパスワードを入力してください。"] {
            XCTAssertNil(DialogPolicy.rejection(for: .init(trustedProvider: true, passwordFields: 1,
                accountFields: 1, canWritePassword: true, canSubmit: true, passwordIsEmpty: true, context: text)))
        }
    }

    func testRefusesSpoofedUnavailableAndAmbiguousForms() {
        let cases: [DialogFacts] = [
            .init(trustedProvider: false, passwordFields: 1, accountFields: 1, canWritePassword: true, canSubmit: true, passwordIsEmpty: true),
            .init(trustedProvider: true, passwordFields: 2, accountFields: 0, canWritePassword: true, canSubmit: true, passwordIsEmpty: true),
            .init(trustedProvider: true, passwordFields: 1, accountFields: 2, canWritePassword: true, canSubmit: true, passwordIsEmpty: true),
            .init(trustedProvider: true, passwordFields: 1, accountFields: 0, canWritePassword: false, canSubmit: true, passwordIsEmpty: true),
            .init(trustedProvider: true, passwordFields: 1, accountFields: 0, canWritePassword: true, canSubmit: false, passwordIsEmpty: true),
            .init(trustedProvider: true, passwordFields: 1, accountFields: 0, canWritePassword: true, canSubmit: true, passwordIsEmpty: false)
        ]
        for facts in cases { XCTAssertNotNil(DialogPolicy.rejection(for: facts)) }
    }

    func testRefusesCredentialsThatAreNotLocalAccountPasswords() {
        for context in ["Apple Account", "Apple ID", "iCloud", "disk password", "磁盘密码", "钥匙串密码", "キーチェーン", "network password"] {
            let facts = DialogFacts(trustedProvider: true, passwordFields: 1, accountFields: 0,
                                    canWritePassword: true, canSubmit: true, passwordIsEmpty: true, context: context)
            XCTAssertNotNil(DialogPolicy.rejection(for: facts), context)
        }
    }

    func testCredentialsRejectEmptyAndNewlinesButPreservePasswordWhitespace() throws {
        XCTAssertThrowsError(try Credentials(account: "", password: "valid"))
        XCTAssertThrowsError(try Credentials(account: "tubao", password: ""))
        XCTAssertThrowsError(try Credentials(account: "tubao", password: "a\nb"))
        let credentials = try Credentials(account: " tubao ", password: "  p a s s  ")
        XCTAssertEqual(credentials.account, "tubao")
        XCTAssertEqual(credentials.password, "  p a s s  ")
    }
}
