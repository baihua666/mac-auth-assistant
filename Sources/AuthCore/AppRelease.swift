import Foundation

public enum UpdateChannel: String, CaseIterable, Sendable {
    case stable, preview
    public var label: String { self == .stable ? "正式版" : "正式版与预览版" }
}
public struct UpdateError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct AppRelease: Identifiable, Equatable, Sendable {
    public static let repository = "baihua666/mac-auth-assistant"
    public static let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!
    public let tag: String
    public let version: AppVersion
    public let build: Int
    public let notes: String
    public let publishedAt: Date?
    public let prerelease: Bool
    public let pageURL: URL
    public let asset: Asset?
    public var id: String { "\(tag):\(build)" }
    public struct Asset: Equatable, Sendable {
        public let name: String
        public let url: URL
        public let size: Int64
        public let sha256: String
    }
    private struct Payload: Decodable {
        struct File: Decodable {
            let name: String; let browser_download_url: URL; let size: Int64; let digest: String?
        }
        let tag_name: String; let draft: Bool; let prerelease: Bool
        let body: String?; let published_at: Date?; let html_url: URL; let assets: [File]
    }
    public static func isRepositoryURL(_ url: URL, prefix: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil &&
            url.port == nil && url.query == nil && url.fragment == nil && url.path.hasPrefix("/\(repository)/\(prefix)")
    }
    public static func decode(_ data: Data, architecture: String) throws -> [Self] {
        guard data.count <= 4_194_304 else { throw UpdateError("发行目录过大，请稍后重试") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Payload].self, from: data).compactMap { item -> Self? in
            guard !item.draft, let version = AppVersion(item.tag_name),
                  isRepositoryURL(item.html_url, prefix: "releases/tag/"),
                  item.html_url.lastPathComponent == item.tag_name else { return nil }
            let stem = "MacAuthAssistant-\(version.description)-b"
            var matched: (Int, Asset)?
            for file in item.assets {
                guard file.name.hasPrefix(stem), file.name.hasSuffix("-\(architecture).zip") || file.name.hasSuffix("-universal.zip") else { continue }
                let suffix = file.name.hasSuffix("-universal.zip") ? "-universal.zip" : "-\(architecture).zip"
                let number = String(file.name.dropFirst(stem.count).dropLast(suffix.count))
                guard let build = Int(number), build > 0, String(build) == number,
                      let digest = file.digest, digest.range(of: "^sha256:[a-f0-9]{64}$", options: .regularExpression) != nil,
                      file.size > 0, file.size <= 104_857_600,
                      isRepositoryURL(file.browser_download_url, prefix: "releases/download/"),
                      file.browser_download_url.path == "/\(repository)/releases/download/\(item.tag_name)/\(file.name)" else { continue }
                let asset = Asset(name: file.name, url: file.browser_download_url, size: file.size, sha256: String(digest.dropFirst(7)))
                if matched == nil || build > matched!.0 { matched = (build, asset) }
            }
            return Self(tag: item.tag_name, version: version, build: matched?.0 ?? 0,
                        notes: String((item.body ?? "暂无发行说明").prefix(30_000)), publishedAt: item.published_at,
                        prerelease: item.prerelease || !version.prerelease.isEmpty, pageURL: item.html_url, asset: matched?.1)
        }.sorted { a, b in a.version == b.version ? a.build > b.build : a.version > b.version }
    }
    public static func newest(in releases: [Self], current: AppVersion, build: Int,
                              channel: UpdateChannel, skipped: String? = nil) -> Self? {
        releases.first { (channel == .preview || !$0.prerelease) && $0.id != skipped &&
            $0.version.isNewer(than: current, build: $0.build, currentBuild: build) }
    }
}
