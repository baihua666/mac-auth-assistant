import Foundation
import AuthCore

@MainActor
final class RuntimeValidation {
    private(set) var evidence: ValidationEvidence?
    private(set) var persistenceFailed = false
    private var associatedWindow: String?
    private let destination = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacAuthAssistant/validation.json")

    var active: Bool { evidence?.result == .pending }
    var prompt: String { "Mac 授权助手管理员自检 · \(evidence?.id.uuidString ?? "")" }

    func start() -> String {
        evidence = ValidationEvidence()
        associatedWindow = nil
        persistenceFailed = false
        persist()
        return prompt
    }

    func matches(_ dialog: DetectedDialog) -> Bool {
        active && (associatedWindow == dialog.id || dialog.context.contains(prompt))
    }

    func associate(_ dialogs: [DetectedDialog]) {
        guard active, associatedWindow == nil else { return }
        if let exact = dialogs.first(where: { $0.context.contains(prompt) }) {
            associatedWindow = exact.id
        } else if dialogs.count == 1, let dialog = dialogs.first, dialog.isNewWindow,
                  dialog.context.contains("MacAuthAssistant") || dialog.context.contains("Mac 授权助手") {
            // Authorization rules can replace the custom prompt with the requesting app's name.
            associatedWindow = dialog.id
        }
    }

    func record(_ stage: ValidationStage, seconds: Int? = nil, code: Int32? = nil) {
        guard active else { return }
        evidence?.record(stage, seconds: seconds, code: code)
        persist()
    }

    func observe(_ snapshot: ValidationObservation) {
        guard active, evidence?.observation != snapshot else { return }
        evidence?.observation = snapshot
        persist()
    }

    func finish(status: Int32) {
        evidence?.finish(status: status)
        persist()
    }

    private func persist() {
        guard let evidence else { return }
        do {
            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(evidence).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch { persistenceFailed = true }
    }
}
