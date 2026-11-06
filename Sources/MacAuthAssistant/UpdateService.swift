import Foundation
import CryptoKit
import AuthCore

protocol UpdateServing: Sendable {
    func releases(architecture: String) async throws -> [AppRelease]
    func download(_ asset: AppRelease.Asset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

struct GitHubUpdateService: UpdateServing {
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }
    func releases(architecture: String) async throws -> [AppRelease] {
        var request = URLRequest(url: AppRelease.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacAuthAssistant", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError("GitHub 没有返回有效响应，请重试") }
        switch http.statusCode {
        case 200: return try AppRelease.decode(data, architecture: architecture)
        case 403, 429: throw UpdateError("GitHub 请求暂受限，请稍后重试")
        case 404: throw UpdateError("公开发行源暂不可用，请稍后重试")
        default: throw UpdateError("检查更新失败（HTTP \(http.statusCode)），请重试")
        }
    }
    func download(_ asset: AppRelease.Asset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacAuthAssistant-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = folder.appendingPathComponent("update.zip")
        do {
            var request = URLRequest(url: asset.url, timeoutInterval: 180)
            request.setValue("MacAuthAssistant", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let url = http.url, url.scheme == "https",
                  ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "") else {
                throw UpdateError("安装包下载失败，请重试")
            }
            FileManager.default.createFile(atPath: path.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            var hash = SHA256(); var chunk = Data(); var received: Int64 = 0
            for try await byte in bytes {
                chunk.append(byte); received += 1
                guard received <= asset.size else { throw UpdateError("安装包大小超出发行记录，下载已停止") }
                if chunk.count == 131_072 {
                    try Task.checkCancellation(); hash.update(data: chunk); try handle.write(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true); progress(Double(received) / Double(asset.size))
                }
            }
            try Task.checkCancellation(); hash.update(data: chunk); try handle.write(contentsOf: chunk)
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard received == asset.size, digest == asset.sha256 else { throw UpdateError("安装包大小或 SHA-256 校验失败，请重新检查更新") }
            progress(1); return path
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
