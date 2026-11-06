import XCTest
import CryptoKit
import AuthCore
@testable import MacAuthAssistant

private final class UpdateProtocolFixture: URLProtocol {
    // Each request carries its own immutable fixture; no process-global response state.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let code = Int(request.value(forHTTPHeaderField: "Fixture-Status") ?? "200")!
        let content = Data((request.value(forHTTPHeaderField: "Fixture-Body") ?? "[]").utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: content)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class UpdateServiceTests: XCTestCase {
    func service(status: Int = 200, body: String = "[]") -> GitHubUpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateProtocolFixture.self]
        configuration.httpAdditionalHeaders = ["Fixture-Status": String(status), "Fixture-Body": body]
        return GitHubUpdateService(session: URLSession(configuration: configuration))
    }
    func asset(digest: String) throws -> AppRelease.Asset {
        let file = "MacAuthAssistant-0.3.0-b15-arm64.zip"
        let data = try JSONSerialization.data(withJSONObject: [["tag_name": "v0.3.0", "draft": false, "prerelease": false,
            "html_url": "https://github.com/baihua666/mac-auth-assistant/releases/tag/v0.3.0", "assets": [["name": file,
            "size": 2, "digest": "sha256:" + digest,
            "browser_download_url": "https://github.com/baihua666/mac-auth-assistant/releases/download/v0.3.0/\(file)"]]]])
        return try XCTUnwrap(AppRelease.decode(data, architecture: "arm64").first?.asset)
    }
    func testNoReleasesAndRateLimitAreNotConfused() async throws {
        let values = try await service().releases(architecture: "arm64")
        XCTAssertTrue(values.isEmpty)
        do {
            _ = try await service(status: 403).releases(architecture: "arm64")
            XCTFail("HTTP errors cannot mean up to date")
        } catch { XCTAssertTrue(error.localizedDescription.contains("受限")) }
    }
    func testChecksumRequiredForDownloadedBytes() async throws {
        let checksum = SHA256.hash(data: Data("[]".utf8)).map { String(format: "%02x", $0) }.joined()
        let path = try await service().download(asset(digest: checksum)) { _ in }
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        XCTAssertEqual(try Data(contentsOf: path), Data("[]".utf8))
        do {
            _ = try await service().download(asset(digest: String(repeating: "0", count: 64))) { _ in }
            XCTFail("Changed bytes cannot be installed")
        } catch { XCTAssertTrue(error.localizedDescription.contains("SHA-256")) }
    }
}
