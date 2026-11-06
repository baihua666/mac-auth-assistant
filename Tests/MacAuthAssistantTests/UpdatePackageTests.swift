import XCTest
import AuthCore
import CryptoKit
@testable import MacAuthAssistant

final class UpdatePackageTests: XCTestCase {
    func testLocallyPackagedSignedReleaseWhenExplicitlyProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let archivePath = environment["MACAUTH_UPDATE_ARCHIVE"], let installedPath = environment["MACAUTH_CURRENT_APPLICATION"] else {
            throw XCTSkip("Optional signed-package integration needs an explicitly supplied local archive and installed application")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Version.json"))) as? [String: Any])
        let version = try XCTUnwrap(metadata["version"] as? String), build = try XCTUnwrap(metadata["build"] as? Int)
        let file = "MacAuthAssistant-\(version)-b\(build)-\(BuildIdentity.architecture).zip"
        let bytes = try Data(contentsOf: URL(fileURLWithPath: archivePath))
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let payload = try JSONSerialization.data(withJSONObject: [["tag_name": "v\(version)", "draft": false, "prerelease": false,
            "html_url": "https://github.com/baihua666/mac-auth-assistant/releases/tag/v\(version)", "assets": [["name": file,
            "size": bytes.count, "digest": "sha256:" + digest,
            "browser_download_url": "https://github.com/baihua666/mac-auth-assistant/releases/download/v\(version)/\(file)"]]]])
        let release = try XCTUnwrap(AppRelease.decode(payload, architecture: BuildIdentity.architecture).first)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let archive = folder.appendingPathComponent("update.zip"); try bytes.write(to: archive)
        let candidate = try UpdatePackage.unpack(archive: archive, release: release, current: URL(fileURLWithPath: installedPath))
        XCTAssertEqual(Bundle(url: candidate)?.infoDictionary?["MacAuthVersion"] as? String, version)
    }
    func testArchiveTraversalAndSymlinksAreRejected() throws {
        let listing = "-rwxr-xr-x  2.0 unx 1024 b- defN 00-Jan-01 file"
        XCTAssertNoThrow(try UpdatePackage.validateArchive(names: "MacAuthAssistant.app/Contents/MacOS/MacAuthAssistant\n", listing: listing))
        for path in ["/tmp/evil", "MacAuthAssistant.app/../../evil", "Other.app/Contents/file", "MacAuthAssistant.app/./file", "MacAuthAssistant.app/Contents/..\\evil"] {
            XCTAssertThrowsError(try UpdatePackage.validateArchive(names: path, listing: listing))
        }
        XCTAssertThrowsError(try UpdatePackage.validateArchive(names: "MacAuthAssistant.app/link", listing: "lrwxr-xr-x 2.0 unx 8 b- defN file"))
        XCTAssertThrowsError(try UpdatePackage.validateArchive(names: "MacAuthAssistant.app/huge", listing: "-rw-r--r-- 2.0 unx 999999999 b- defN file"))
    }
    func testMetadataMismatchAndUnsupportedOSAreRejectedBeforeInstall() throws {
        let data = Data("""
        [{"tag_name":"v0.3.0","draft":false,"prerelease":false,"html_url":"https://github.com/baihua666/mac-auth-assistant/releases/tag/v0.3.0","assets":[]}]
        """.utf8)
        let release = try XCTUnwrap(AppRelease.decode(data, architecture: "arm64").first)
        var info: [String: Any] = ["CFBundleIdentifier": "local.mac-auth-assistant", "CFBundleExecutable": "MacAuthAssistant",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "0", "LSMinimumSystemVersion": "13.0"]
        let os = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        XCTAssertNoThrow(try UpdatePackage.inspect(info, release: release, os: os))
        info["CFBundleIdentifier"] = "other.app"; XCTAssertThrowsError(try UpdatePackage.inspect(info, release: release, os: os))
        info["CFBundleIdentifier"] = "local.mac-auth-assistant"; info["CFBundleVersion"] = "99"
        XCTAssertThrowsError(try UpdatePackage.inspect(info, release: release, os: os))
        info["CFBundleVersion"] = "0"; info["LSMinimumSystemVersion"] = "15.0"
        XCTAssertThrowsError(try UpdatePackage.inspect(info, release: release, os: os))
    }
    func testUnsignedApplicationsCannotEstablishUpdateTrust() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertThrowsError(try UpdatePackage.verifySignature(candidate: folder, current: folder))
    }
}
