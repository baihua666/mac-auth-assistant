import XCTest
@testable import AuthCore

final class PermissionPolicyTests: XCTestCase {
    private func facts(_ text: String, _ labels: [String], trusted: Bool = true, passwords: Int = 0) -> PermissionFacts {
        PermissionFacts(trustedProvider: trusted, passwordFields: passwords, text: text,
                        buttons: labels.map { AuthButton(labels: [$0], supportsPress: true) })
    }
    func testRecognizesSystemPermissionCategoriesAndExactAllowButtons() {
        let fixtures: [(String, PermissionCategory)] = [
            ("Sample wants to access files in your Documents folder.", .files),
            ("ScreenRecorder wants to access files in your Documents folder.", .files),
            ("Allow Sample to find devices on local networks?", .localNetwork),
            ("Sample would like to access the camera.", .camera),
            ("Sample would like to access your microphone.", .microphone),
            ("Sample is requesting to directly access your screen and audio.", .screen),
            ("Sample would like to access your location.", .location),
            ("Sample would like to access your contacts.", .contacts),
            ("Sample would like to send you notifications.", .notifications)
        ]
        for (text, category) in fixtures {
            let result = PermissionPolicy.decide(facts(text, ["Don't Allow", "Allow"]))
            XCTAssertEqual(result.match?.category, category, text)
            XCTAssertEqual(result.match?.buttonIndex, 1, text)
        }
    }
    func testChineseJapaneseAndOncePreference() {
        XCTAssertEqual(PermissionPolicy.decide(facts("“Sample”想要访问麦克风。", ["不允许", "好"])).match?.category, .microphone)
        XCTAssertEqual(PermissionPolicy.decide(facts("Sampleがカメラへのアクセスを求めています。", ["許可しない", "許可"])).match?.category, .camera)
        XCTAssertEqual(PermissionPolicy.decide(facts("“Sample”想给您发送通知。", ["不允许", "允许"])).match?.category, .notifications)
        XCTAssertEqual(PermissionPolicy.decide(facts("Sampleからの通知を許可しますか？", ["許可しない", "許可"])).match?.category, .notifications)
        XCTAssertEqual(PermissionPolicy.decide(facts("“Sample”想使用麦克风。", ["不允许", "好"])).match?.category, .microphone)
        XCTAssertEqual(PermissionPolicy.decide(facts("Sample would like to access your location.",
                                                    ["Don't Allow", "Allow While Using App", "Allow Once"])).match?.buttonIndex, 2)
    }
    func testRefusesDestructiveUnknownPasswordAndUntrustedDialogs() {
        XCTAssertNil(PermissionPolicy.decide(facts("Delete files from Documents folder?", ["Cancel", "OK"])).match)
        XCTAssertNil(PermissionPolicy.decide(facts("Continue transaction?", ["Cancel", "Allow"])).match)
        XCTAssertNil(PermissionPolicy.decide(facts("Camera application stopped unexpectedly.", ["Cancel", "Allow"])).match)
        XCTAssertNil(PermissionPolicy.decide(facts("Sample wants access to the camera", ["Cancel", "Allow"], trusted: false)).match)
        XCTAssertNil(PermissionPolicy.decide(facts("Sample wants access to the camera", ["Cancel", "Allow"], passwords: 1)).match)
        XCTAssertNil(PermissionPolicy.decide(facts("Sample wants to access your microphone", ["Don't Allow", "Open System Settings"])).match)
    }
    func testRejectsSelfPermissionGatesAndSoftwareWarnings() {
        for text in ["MacAuthAssistant wants to access your camera",
                     "Sample wants camera access, Apple cannot check for malicious software"] {
            XCTAssertNil(PermissionPolicy.decide(facts(text, ["Don't Allow", "Allow"])).match, text)
        }
    }
    func testAmbiguousButtonsAreRejectedAndDefaultButtonDoesNotOverrideRules() {
        XCTAssertNil(PermissionPolicy.decide(facts("Sample wants to access your camera", ["Allow", "Allow"])).match)
        let f = PermissionFacts(trustedProvider: true, passwordFields: 0, text: "Sample wants to access your camera",
                                buttons: [AuthButton(labels: ["Cancel"], supportsPress: true, isDefault: true),
                                          AuthButton(labels: ["Allow"], supportsPress: true)])
        XCTAssertEqual(PermissionPolicy.decide(f).match?.buttonIndex, 1)
    }
    func testQueueKeepsCurrentWindowAndThenMovesToNext() {
        XCTAssertEqual(PermissionPolicy.chooseWindow(eligible: ["B", "A"], current: "A"), "A")
        XCTAssertEqual(PermissionPolicy.chooseWindow(eligible: ["B"], current: "A"), "B")
        XCTAssertNil(PermissionPolicy.chooseWindow(eligible: [], current: "A"))
    }
}
