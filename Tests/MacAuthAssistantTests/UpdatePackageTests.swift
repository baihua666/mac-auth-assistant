import XCTest
import AuthCore
@testable import MacAuthAssistant

final class UpdatePackageTests: XCTestCase {
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
