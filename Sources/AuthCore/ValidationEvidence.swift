import Foundation

public enum ValidationStage: String, Codable {
    case requestStarted, dialogSeen, countdown, passwordWritten, confirmationSent
    case manualInteraction, submissionStopped, osFinished
}

public enum ValidationResult: String, Codable {
    case pending, passed, failed, interrupted, incomplete, notExercised

    public var label: String {
        switch self {
        case .pending: return "自检进行中"
        case .passed: return "完整自动流程通过"
        case .failed: return "系统未通过授权"
        case .interrupted: return "存在手动操作，本轮不计为自动通过"
        case .incomplete: return "自动处理阶段不完整"
        case .notExercised: return "未观察到本次真实弹窗，不计为通过"
        }
    }
}

public struct ValidationEntry: Codable {
    public let stage: ValidationStage
    public let at: Date
    public let seconds: Int?
    public let code: Int32?
}

public struct ValidationObservation: Codable, Equatable {
    public var providers = 0
    public var trustedProviders = 0
    public var windows = 0
    public var passwordFields = 0
    public var focused = false
    public var matchingProbe = false
    public var canWrite = false
    public var canSubmit = false
    public var inputEmpty = false
    public var passwordState: PasswordInputState = .unknown
    public var contextPresent = false
    public var submitIsButton = false
    public init() {}
}

/// Contains only typed stages, counts and OS return codes; no arbitrary UI text or credentials.
public struct ValidationEvidence: Codable {
    public let id: UUID
    public let startedAt: Date
    public private(set) var events: [ValidationEntry] = []
    public private(set) var result: ValidationResult = .pending
    public private(set) var osStatus: Int32?
    public var observation = ValidationObservation()

    public init() {
        id = UUID()
        startedAt = Date()
        record(.requestStarted)
    }

    public mutating func record(_ stage: ValidationStage, seconds: Int? = nil, code: Int32? = nil) {
        guard result == .pending else { return }
        if let last = events.last, last.stage == stage, last.seconds == seconds, last.code == code { return }
        events.append(ValidationEntry(stage: stage, at: Date(), seconds: seconds, code: code))
    }

    public mutating func finish(status: Int32) {
        guard result == .pending else { return }
        record(.osFinished, code: status)
        osStatus = status
        if status != 0 { result = .failed; return }
        if events.contains(where: { $0.stage == .manualInteraction }) { result = .interrupted; return }
        guard events.contains(where: { $0.stage == .dialogSeen }) else { result = .notExercised; return }
        let path: [ValidationStage] = [.dialogSeen, .countdown, .passwordWritten, .confirmationSent]
        var index = 0
        for event in events where index < path.count {
            if event.stage == path[index] { index += 1 }
        }
        result = index == path.count ? .passed : .incomplete
    }
}
