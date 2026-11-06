import Foundation
import AuthCore

enum UpdateInstaller {
    static var resultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacAuthAssistant/update-result.txt")
    }
    static func launch(candidate: URL, current: URL = Bundle.main.bundleURL) throws {
        let fm = FileManager.default
        guard current.pathExtension == "app", !current.path.hasPrefix("/Volumes/"),
              fm.isWritableFile(atPath: current.deletingLastPathComponent().path),
              current.resolvingSymlinksInPath().standardizedFileURL == current.standardizedFileURL else {
            throw UpdateError("应用目录不可写或正在磁盘映像中运行，请移到 Applications 后重试")
        }
        let requirement = try UpdatePackage.verifySignature(candidate: candidate, current: current)
        let work = current.deletingLastPathComponent().appendingPathComponent(".MacAuthAssistant-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let staged = work.appendingPathComponent("next.app")
            try fm.copyItem(at: candidate, to: staged)
            let helper = work.appendingPathComponent("install.sh")
            try fm.copyItem(at: current.appendingPathComponent("Contents/Resources/InstallUpdate.sh"), to: helper)
            let requirementFile = work.appendingPathComponent("requirement.txt")
            try requirement.write(to: requirementFile, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requirementFile.path)
            try fm.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), current.path, work.path, resultURL.path]
            process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            try? fm.removeItem(at: work); throw error
        }
    }
}
