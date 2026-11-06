import AppKit
import AuthCore

extension AppState {
    func recoverFocus(dialogs: [DetectedDialog], focused: DetectedDialog?) -> DetectedDialog? {
        focusGate.retain(visible: Set(dialogs.map(\.id)))
        guard automationConditions.isReady else { return focused }
        if let focused { diagnostics.recordFocus(.focused); return focused }
        if pending != nil { pauseForFocusRecovery() }
        let candidates = dialogs.filter {
            !gate.isSuppressed($0.id) && activity.blockingRule(for: $0.activityRequest, text: $0.context) == nil &&
                DialogPolicy.rejection(for: $0.facts, allowUnreadableInput: true) == nil
        }
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        guard focusGate.request(candidate.id, now: ProcessInfo.processInfo.systemUptime, lastInput: lastHumanInputAt) else {
            if focusGate.isExhausted(candidate.id) {
                diagnostics.recordFocus(.failed)
                activity.observe(token: candidate.activityToken, request: candidate.activityRequest)
                activity.finish(token: candidate.activityToken, outcome: .failed, reason: "两次自动聚焦均未成功，未输入密码")
                status = "自动聚焦未成功，本窗口已停止聚焦尝试；未输入密码"
            }
            return nil
        }
        let result = focusController.request(candidate)
        diagnostics.recordFocus(result)
        status = "正在自动聚焦系统授权窗口；确认焦点后开始倒计时"
        return nil // Give the WindowServer a run-loop turn; never treat a requested focus as acquired.
    }

    func pauseForFocusRecovery() {
        generation += 1
        gate.pauseForFocusLoss()
        pending = nil
        remaining = nil
        hideCountdown?()
        status = "授权窗口失去焦点，正在重新聚焦；恢复后重新倒计时"
    }

    func handleGlobalInput(at timestamp: TimeInterval, isKeyboard: Bool, location: CGPoint?) {
        lastHumanInputAt = max(lastHumanInputAt, timestamp)
        permissions.handleInput(at: timestamp, isKeyboard: isKeyboard, location: location)
        guard remaining != nil || (processing && !awaitingResult) else { return }
        let inDialog: Bool
        if let pending {
            inDialog = isKeyboard ? scanner.isFocused(pending) :
                (location.flatMap { point in DialogFocusController.bounds(pending.window).map { $0.contains(point) } } ?? true)
        } else { inDialog = true }
        guard inDialog else { pauseForFocusRecovery(); return }
        let startedAt = gate.startedAt
        let cancelled = gate.cancelForInteraction(at: timestamp)
        if let startedAt { diagnostics.recordInteraction(cancelled: cancelled, offset: timestamp - startedAt) }
        if cancelled { cancelCurrent(message: "检测到授权窗口内的手动操作，本次自动处理已取消") }
    }
}
