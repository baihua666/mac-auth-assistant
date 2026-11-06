import ApplicationServices
import AuthCore

extension AppState {
    func recordSubmission(_ stage: ValidationStage, dialog: DetectedDialog, code: Int32? = nil) {
        activity.observe(token: dialog.activityToken, request: dialog.activityRequest)
        if !administratorBlocked(dialog) {
            if stage == .submissionStopped {
                activity.finish(token: dialog.activityToken, outcome: .failed, reason: "自动提交已停止（阶段码 \(code ?? 0)），未验证原操作成功")
            } else if stage == .confirmationSent || stage == .passwordWritten {
                activity.finish(token: dialog.activityToken, outcome: .submitted,
                                reason: stage == .confirmationSent ? "已发送确认，等待系统弹窗关闭" : "已发送密码输入，等待确认")
            }
        }
        diagnostics.record(stage, code: code)
        if validation.matches(dialog) { validation.record(stage, code: code) }
    }

    var automationConditions: AutomationConditions {
        AutomationConditions(enabled: enabled && !activity.loadFailed, hasCredentials: hasCredentials,
                             accessibilityGranted: AXIsProcessTrusted(), suspended: suspended,
                             settingsVisible: settingsVisible)
    }

    func observation(dialogs: [DetectedDialog], focused: DetectedDialog?) -> ValidationObservation {
        var observation = ValidationObservation()
        observation.providers = scanner.providerCount
        observation.trustedProviders = scanner.trustedProviderCount
        observation.windows = dialogs.count
        observation.passwordFields = dialogs.reduce(0) { $0 + $1.facts.passwordFields }
        observation.focused = focused != nil
        observation.matchingProbe = dialogs.contains { validation.matches($0) }
        observation.canWrite = focused?.facts.canWritePassword ?? false
        observation.canSubmit = focused?.facts.canSubmit ?? false
        observation.inputEmpty = focused?.facts.passwordIsEmpty ?? false
        observation.passwordState = focused?.facts.passwordState ?? .unknown
        observation.contextPresent = dialogs.contains { !$0.context.isEmpty }
        observation.submitIsButton = focused?.submitElement.map { AX.string($0, kAXRoleAttribute) == kAXButtonRole } ?? false
        return observation
    }

    func recordRuntime(dialogs: [DetectedDialog], focused: DetectedDialog?) {
        let conditions = automationConditions
        let reason = focused.flatMap { rejection(for: $0) }
        let block: AutomationBlock
        if !enabled { block = .disabled }
        else if !hasCredentials { block = .credentials }
        else if !conditions.accessibilityGranted { block = .accessibility }
        else if suspended { block = .suspended }
        else if processing { block = .processing }
        else if dialogs.isEmpty { block = .noWindow }
        else if focused == nil { block = .notFocused }
        else if reason != nil { block = .dialogPolicy }
        else if remaining == nil { block = .cancelledOrConsumed }
        else { block = .none }
        diagnostics.observe(conditions: conditions, observation: observation(dialogs: dialogs, focused: focused),
                            block: block, rejection: reason, remaining: remaining)
    }
}
