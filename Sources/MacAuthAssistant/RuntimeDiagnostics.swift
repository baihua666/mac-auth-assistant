import Foundation
import AuthCore

enum AutomationBlock: String, Codable {
    case none, disabled, credentials, accessibility, suspended, processing
    case noWindow, notFocused, dialogPolicy, cancelledOrConsumed
}

/// The latest ordinary-operation snapshot; never contains credential or raw UI text.
@MainActor
final class RuntimeDiagnostics {
    private struct Snapshot: Codable {
        var at = Date()
        var conditions: AutomationConditions?
        var observation = ValidationObservation()
        var block: AutomationBlock = .disabled
        var rejection: String?
        var remaining: Int?
        var lastAction: ValidationStage?
        var lastActionAt: Date?
        var stopCode: Int32?
        var interactionCancelled: Bool?
        var interactionOffsetSeconds: TimeInterval?
        var loginItemState: LoginItemState?
        var loginItemErrorCode: Int?
        var focusResult: DialogFocusResult?
        var focusAt: Date?
    }

    private var snapshot = Snapshot()
    private var lastWrite = Date.distantPast
    private let destination: URL
    private(set) var persistenceFailed = false

    init(destination: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacAuthAssistant/runtime.json")) {
        self.destination = destination
    }

    func observe(conditions: AutomationConditions, observation: ValidationObservation,
                 block: AutomationBlock, rejection: String?, remaining: Int?) {
        let changed = snapshot.conditions != conditions || snapshot.observation != observation ||
            snapshot.block != block || snapshot.rejection != rejection || snapshot.remaining != remaining
        snapshot.conditions = conditions
        snapshot.observation = observation
        snapshot.block = block
        snapshot.rejection = rejection
        snapshot.remaining = remaining
        if changed || Date().timeIntervalSince(lastWrite) >= 5 { persist() }
    }

    func record(_ stage: ValidationStage, code: Int32? = nil) {
        snapshot.lastAction = stage
        snapshot.lastActionAt = Date()
        snapshot.stopCode = code
        persist()
    }

    func recordInteraction(cancelled: Bool, offset: TimeInterval) {
        guard offset.isFinite else { return }
        snapshot.interactionCancelled = cancelled
        snapshot.interactionOffsetSeconds = offset
        persist()
    }

    func recordLoginItem(_ state: LoginItemState, errorCode: Int? = nil) {
        snapshot.loginItemState = state
        snapshot.loginItemErrorCode = errorCode
        persist()
    }

    func recordFocus(_ result: DialogFocusResult) {
        guard snapshot.focusResult != result else { return }
        snapshot.focusResult = result
        snapshot.focusAt = Date()
        persist()
    }

    private func persist() {
        do {
            snapshot.at = Date()
            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            lastWrite = snapshot.at
            persistenceFailed = false
        } catch { persistenceFailed = true }
    }
}
