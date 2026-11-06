import Foundation
import AuthCore

enum PermissionStage: String, Codable { case countdown, cancelled, sent, closed, stillVisible, rejected, failed }
struct PermissionEntry: Codable {
    let at: Date
    let category: PermissionCategory?
    let stage: PermissionStage
    let rejection: PermissionRejection?
    let code: Int32?
}

@MainActor
final class PermissionJournal {
    private struct Report: Codable {
        var at = Date()
        var enabled = false
        var windows = 0
        var providers = 0
        var trustedProviders = 0
        var windowReadCodes: [Int32] = []
        var remaining: Int?
        var events: [PermissionEntry] = []
    }
    private var report = Report()
    private let destination: URL
    private var lastWrite = Date.distantPast
    private(set) var persistenceFailed = false
    init(destination: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacAuthAssistant/permissions.json")) {
        self.destination = destination
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: destination), data.count <= 100_000,
           var previous = try? decoder.decode(Report.self, from: data) {
            previous.events = Array(previous.events.suffix(50))
            report = previous
        }
    }
    func observe(enabled: Bool, windows: Int, remaining: Int?, providers: Int = 0, trustedProviders: Int = 0, windowReadCodes: [Int32] = []) {
        let changed = report.enabled != enabled || report.windows != windows || report.remaining != remaining
        report.enabled = enabled; report.windows = windows; report.remaining = remaining
        report.providers = providers; report.trustedProviders = trustedProviders; report.windowReadCodes = windowReadCodes
        if changed || Date().timeIntervalSince(lastWrite) >= 5 { persist() }
    }
    func record(_ stage: PermissionStage, category: PermissionCategory?, rejection: PermissionRejection? = nil, code: Int32? = nil) {
        report.events.append(PermissionEntry(at: Date(), category: category, stage: stage, rejection: rejection, code: code))
        report.events = Array(report.events.suffix(50))
        persist()
    }
    private func persist() {
        do {
            report.at = Date()
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            lastWrite = report.at
            persistenceFailed = false
        } catch { persistenceFailed = true }
    }
}
