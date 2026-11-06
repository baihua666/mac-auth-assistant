import Foundation
import AuthCore

struct BuildIdentity: Sendable {
    let version: AppVersion
    let build: Int
    let revision: String
    var label: String { "\(version)（构建 \(build)）" }
    static func read(_ bundle: Bundle = .main) -> Self {
        Self(version: AppVersion((bundle.infoDictionary?["MacAuthVersion"] ?? bundle.infoDictionary?["CFBundleShortVersionString"]) as? String ?? "") ?? AppVersion("0.0.0")!,
             build: Int(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0,
             revision: bundle.infoDictionary?["MacAuthSourceRevision"] as? String ?? "本地源码")
    }
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
