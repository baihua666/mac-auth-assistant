import XCTest
import AuthCore
@testable import MacAuthAssistant

private actor ReleaseFixture: UpdateServing {
    var requests = 0
    var fail = false
    var values: [AppRelease] = []
    func configure(_ values: [AppRelease], fail: Bool = false) { self.values = values; self.fail = fail }
    func releases(architecture: String) async throws -> [AppRelease] {
        requests += 1
        if fail { throw UpdateError("请求受限，请重试") }
        return values
    }
    func download(_ asset: AppRelease.Asset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw UpdateError("测试不下载或安装真实程序")
    }
}
final class UpdateControllerTests: XCTestCase {
    func releases() throws -> [AppRelease] {
        let file = "MacAuthAssistant-0.3.0-b15-\(BuildIdentity.architecture).zip"
        let data = try JSONSerialization.data(withJSONObject: [["tag_name": "v0.3.0", "draft": false, "prerelease": false,
            "html_url": "https://github.com/baihua666/mac-auth-assistant/releases/tag/v0.3.0", "assets": [["name": file,
            "size": 123, "digest": "sha256:" + String(repeating: "a", count: 64),
            "browser_download_url": "https://github.com/baihua666/mac-auth-assistant/releases/download/v0.3.0/\(file)"]]]])
        return try AppRelease.decode(data, architecture: BuildIdentity.architecture)
    }
    @MainActor
    func settle(_ controller: UpdateController) async {
        for _ in 0..<100 where controller.busy { await Task.yield() }
        XCTAssertFalse(controller.busy)
    }
    @MainActor
    func testChecksPersistSettingsAndThrottleAutomaticAttempts() async throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: name)); defer { prefs.removePersistentDomain(forName: name) }
        let fixture = ReleaseFixture(); try await fixture.configure(releases())
        let identity = BuildIdentity(version: AppVersion("0.2.0")!, build: 14, revision: "fixture")
        let model = UpdateController(preferences: prefs, service: fixture, current: identity, readResult: false)
        let now = Date()
        model.checkAutomatically(now: now); await settle(model)
        XCTAssertEqual(model.latest?.version.description, "0.3.0")
        XCTAssertTrue(model.canDownload)
        model.skipSelected()
        XCTAssertNotNil(model.skipped)
        model.checkAutomatically(now: now.addingTimeInterval(60)); await settle(model)
        var count = await fixture.requests; XCTAssertEqual(count, 1)
        model.checkAutomatically(now: now.addingTimeInterval(86_401)); await settle(model)
        XCTAssertNil(model.latest)
        model.check(); await settle(model); XCTAssertNotNil(model.latest)
        model.setAutomatic(false); model.setChannel(.preview)
        let restored = UpdateController(preferences: prefs, service: fixture, current: identity, readResult: false)
        XCTAssertFalse(restored.automatic); XCTAssertEqual(restored.channel, .preview); XCTAssertNotNil(restored.skipped)
        restored.checkAutomatically(now: now.addingTimeInterval(172_800)); await settle(restored)
        count = await fixture.requests; XCTAssertEqual(count, 3)
    }
    @MainActor
    func testNoReleasesErrorCancellationAndDownloadFailureAreDistinct() async throws {
        let name = "local.mac-auth-assistant.tests.\(UUID().uuidString)"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: name)); defer { prefs.removePersistentDomain(forName: name) }
        let fixture = ReleaseFixture()
        let model = UpdateController(preferences: prefs, service: fixture, current: BuildIdentity(version: AppVersion("0.2.0")!, build: 14, revision: "fixture"), readResult: false)
        model.check(); await settle(model)
        XCTAssertTrue(model.message.contains("尚无")); XCTAssertNil(model.errorMessage)
        await fixture.configure([], fail: true)
        model.check(); await settle(model)
        XCTAssertNotNil(model.errorMessage); XCTAssertFalse(model.message.contains("最新"))
        try await fixture.configure(releases())
        model.check(); await settle(model)
        model.download(); await settle(model)
        XCTAssertNotNil(model.errorMessage); XCTAssertFalse(model.canInstall)
        var launched = false, quit = false
        model.install(permitted: true, launch: { _ in launched = true }, quit: { quit = true })
        XCTAssertFalse(launched); XCTAssertFalse(quit)
        model.check(); model.cancel(); await settle(model)
        XCTAssertEqual(model.message, "本次更新操作已取消")
        XCTAssertEqual(model.phase, .idle)
    }
}
