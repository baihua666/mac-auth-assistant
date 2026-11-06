import XCTest
@testable import AuthCore

final class UpdatePolicyTests: XCTestCase {
    func testSemanticVersionsAndBuilds() throws {
        let versions = ["0.2.0-alpha.1", "0.2.0-alpha.2", "0.2.0-beta", "0.2.0-rc.10", "0.2.0", "0.10.0", "1.0.0"]
        let parsed = try versions.map { try XCTUnwrap(AppVersion($0)) }
        XCTAssertEqual(parsed.sorted().map(\.description), versions)
        XCTAssertEqual(AppVersion("v0.2.0+abc"), AppVersion("0.2.0+def"))
        for bad in ["1.0", "01.0.0", "1.0.0-01", "1.0.0-", "1.0.0/../../", String(repeating: "9", count: 50) + ".0.0"] { XCTAssertNil(AppVersion(bad)) }
        let current = try XCTUnwrap(AppVersion("0.2.0"))
        XCTAssertTrue(current.isNewer(than: current, build: 15, currentBuild: 14))
        XCTAssertFalse(current.isNewer(than: current, build: 14, currentBuild: 14))
    }
    func payload(tag: String = "v0.3.0", digest: String? = "sha256:" + String(repeating: "a", count: 64),
                 host: String = "github.com", draft: Bool = false, preview: Bool = false) throws -> Data {
        var asset: [String: Any] = ["name": "MacAuthAssistant-\(tag.dropFirst())-b15-arm64.zip", "size": 123,
            "browser_download_url": "https://\(host)/baihua666/mac-auth-assistant/releases/download/\(tag)/MacAuthAssistant-\(tag.dropFirst())-b15-arm64.zip"]
        asset["digest"] = digest
        return try JSONSerialization.data(withJSONObject: [["tag_name": tag, "draft": draft, "prerelease": preview,
            "html_url": "https://github.com/baihua666/mac-auth-assistant/releases/tag/\(tag)", "body": "发行说明", "assets": [asset]]])
    }
    func testReleaseTrustArchitectureAndMissingPackages() throws {
        let releases = try AppRelease.decode(payload(), architecture: "arm64")
        XCTAssertEqual(releases.first?.build, 15)
        XCTAssertNotNil(releases.first?.asset)
        XCTAssertNil(try AppRelease.decode(payload(), architecture: "x86_64").first?.asset)
        XCTAssertNil(try AppRelease.decode(payload(digest: nil), architecture: "arm64").first?.asset)
        XCTAssertNil(try AppRelease.decode(payload(host: "example.com"), architecture: "arm64").first?.asset)
        XCTAssertTrue(try AppRelease.decode(payload(draft: true), architecture: "arm64").isEmpty)
    }
    func testChannelSkipAndNoDowngrade() throws {
        let current = try XCTUnwrap(AppVersion("0.2.0"))
        let releases = try AppRelease.decode(payload(preview: true), architecture: "arm64")
        XCTAssertNil(AppRelease.newest(in: releases, current: current, build: 14, channel: .stable))
        XCTAssertNotNil(AppRelease.newest(in: releases, current: current, build: 14, channel: .preview))
        XCTAssertNil(AppRelease.newest(in: releases, current: current, build: 14, channel: .preview, skipped: releases[0].id))
        XCTAssertNil(AppRelease.newest(in: releases, current: AppVersion("1.0.0")!, build: 1, channel: .preview))
    }
    func testUniversalReleaseIsAvailableToBothArchitectures() throws {
        var items = try XCTUnwrap(JSONSerialization.jsonObject(with: payload()) as? [[String: Any]])
        var assets = try XCTUnwrap(items[0]["assets"] as? [[String: Any]])
        assets[0]["name"] = (assets[0]["name"] as! String).replacingOccurrences(of: "-arm64.zip", with: "-universal.zip")
        assets[0]["browser_download_url"] = (assets[0]["browser_download_url"] as! String).replacingOccurrences(of: "-arm64.zip", with: "-universal.zip")
        items[0]["assets"] = assets
        let data = try JSONSerialization.data(withJSONObject: items)
        for architecture in ["arm64", "x86_64"] {
            let release = try XCTUnwrap(AppRelease.decode(data, architecture: architecture).first)
            XCTAssertEqual(release.build, 15)
            XCTAssertTrue(release.asset?.name.hasSuffix("-universal.zip") == true)
        }
    }
}
