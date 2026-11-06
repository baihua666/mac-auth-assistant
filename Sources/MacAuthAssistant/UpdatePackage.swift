import Foundation
import Security
import AuthCore

enum UpdatePackage {
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: tool); process.arguments = arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("更新包检查失败（\(URL(fileURLWithPath: tool).lastPathComponent)），当前应用未改动") }
        return String(decoding: data, as: UTF8.self)
    }
    static func validateArchive(names: String, listing: String) throws {
        let entries = names.split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.count < 2000, entries.allSatisfy({ name in
            (name == "MacAuthAssistant.app/" || name.hasPrefix("MacAuthAssistant.app/")) &&
                !name.contains("\\") && !name.split(separator: "/", omittingEmptySubsequences: false).contains("..") &&
                !name.split(separator: "/").contains(".")
        }), !listing.split(separator: "\n").contains(where: { $0.first == "l" }) else {
            throw UpdateError("更新包目录或链接不符合格式，当前应用未改动")
        }
        let fileLines = listing.split(separator: "\n").filter { $0.first == "-" || $0.first == "d" }
        var expanded: Int64 = 0
        for line in fileLines {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count > 3, let size = Int64(fields[3]), size >= 0, size <= 209_715_200 - expanded else {
                throw UpdateError("更新包展开大小异常")
            }
            expanded += size
        }
        guard !fileLines.isEmpty else { throw UpdateError("更新包内容为空") }
    }
    static func inspect(_ info: [String: Any], release: AppRelease, os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) throws {
        guard info["CFBundleIdentifier"] as? String == "local.mac-auth-assistant",
              info["CFBundleExecutable"] as? String == "MacAuthAssistant",
              info["CFBundlePackageType"] as? String == "APPL",
              let version = (info["MacAuthVersion"] ?? info["CFBundleShortVersionString"]) as? String, AppVersion(version) == release.version,
              let build = info["CFBundleVersion"] as? String, Int(build) == release.build,
              let minimum = info["LSMinimumSystemVersion"] as? String else {
            throw UpdateError("安装包的应用标识或版本与发行记录不一致")
        }
        let values = minimum.split(separator: ".").compactMap { Int($0) }
        guard (1...3).contains(values.count), values.count == minimum.split(separator: ".").count else { throw UpdateError("安装包系统要求无效") }
        let required = values + Array(repeating: 0, count: 3 - values.count)
        let actual = [os.majorVersion, os.minorVersion, os.patchVersion]
        guard !actual.lexicographicallyPrecedes(required) else { throw UpdateError("新版需要 macOS \(minimum) 或更高版本") }
    }
    static func verifySignature(candidate: URL, current: URL) throws -> String {
        func code(_ url: URL) throws -> SecStaticCode {
            var value: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &value) == errSecSuccess, let value else { throw UpdateError("无法读取应用签名") }
            return value
        }
        let original = try code(current)
        guard SecStaticCodeCheckValidity(original, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { throw UpdateError("当前应用签名无效，无法安全自动更新") }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(original, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let certs = (information as NSDictionary?)?[kSecCodeInfoCertificates] as? [SecCertificate], !certs.isEmpty else {
            throw UpdateError("审查构建没有稳定签名，请先安装同一开发者签名的版本")
        }
        var requirement: SecRequirement?; var text: CFString?
        guard SecCodeCopyDesignatedRequirement(original, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(try code(candidate), SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else {
            throw UpdateError("新版签名与当前应用不匹配，已阻止安装")
        }
        return text as String
    }
    static func unpack(archive: URL, release: AppRelease, current: URL) throws -> URL {
        let work = archive.deletingLastPathComponent().appendingPathComponent("expanded")
        let names = try run("/usr/bin/zipinfo", ["-1", archive.path])
        let listing = try run("/usr/bin/zipinfo", ["-l", archive.path])
        try validateArchive(names: names, listing: listing)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
        let app = work.appendingPathComponent("MacAuthAssistant.app")
        guard let bundle = Bundle(url: app), let info = bundle.infoDictionary else { throw UpdateError("更新包缺少应用信息") }
        try inspect(info, release: release)
        _ = try verifySignature(candidate: app, current: current)
        guard FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/MacAuthAssistant").path),
              FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/InstallUpdate.sh").path) else { throw UpdateError("更新包缺少可执行文件或更新组件") }
        return app
    }
}
