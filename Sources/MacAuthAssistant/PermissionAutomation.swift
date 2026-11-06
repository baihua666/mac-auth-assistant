import AppKit
import ApplicationServices
import Combine
import AuthCore

@MainActor
final class PermissionAutomation: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var remaining: Int?
    @Published private(set) var category: PermissionCategory?
    @Published private(set) var status = "等待系统权限请求"
    @Published private(set) var diagnosticsFailed = false
    private let preferences: UserDefaults
    private let scanner = PermissionScanner()
    private let journal = PermissionJournal()
    private let activity: ActivityHistory?
    private var gate = CountdownGate()
    private var pending: PermissionWindow?
    private var seen: Set<String> = []
    private var checkingResult = false
    var isProcessing: Bool { checkingResult || remaining != nil }

    init(preferences: UserDefaults = .standard, activity: ActivityHistory? = nil) {
        self.preferences = preferences
        self.activity = activity
        enabled = preferences.object(forKey: "systemPermissionsEnabled") as? Bool ?? true
        preferences.set(enabled, forKey: "systemPermissionsEnabled")
    }
    func setEnabled(_ value: Bool) {
        cancelCurrent(); enabled = value
        preferences.set(value, forKey: "systemPermissionsEnabled")
        status = value ? "等待系统权限请求" : "无密码系统权限自动处理已暂停"
    }
    func cancelCurrent() {
        if let pending { activity?.finish(token: pending.activityToken, outcome: .ignored, reason: "本次权限自动处理已取消") }
        if remaining != nil { journal.record(.cancelled, category: category); status = "本次权限自动处理已取消" }
        gate.cancel(); pending = nil; remaining = nil; category = nil
    }
    func handleInput(at timestamp: TimeInterval, isKeyboard: Bool, location: CGPoint?) {
        guard let pending, remaining != nil else { return }
        let inside = isKeyboard ? AX.focusedPID == pending.pid :
            (location.flatMap { p in DialogFocusController.bounds(pending.window).map { $0.contains(p) } } ?? false)
        if inside && gate.cancelForInteraction(at: timestamp) { cancelCurrent(); status = "检测到权限窗口内手动操作，本次已取消" }
    }
    func tick(allowed: Bool, delay: Int, lastInput: TimeInterval) {
        guard !checkingResult else { return }
        guard allowed else {
            cancelCurrent(); journal.observe(enabled: enabled, windows: 0, remaining: nil); return
        }
        let windows = scanner.scan()
        activity?.reconcile(kind: .permission, visible: Set(windows.map(\.activityToken)))
        for window in windows {
            let blocked = activity?.blockingRule(for: window.activityRequest, text: window.context) != nil
            activity?.observe(token: window.activityToken, request: window.activityRequest,
                              retryIgnored: enabled && !blocked && window.decision.match != nil && !gate.isSuppressed(window.id))
            if blocked {
                _ = activity?.checkBlocked(token: window.activityToken, request: window.activityRequest, text: window.context)
                let message = "命中黑名单，已忽略：\(window.activityRequest.summary)"
                if status != message { status = message }
            } else if !enabled {
                activity?.finish(token: window.activityToken, outcome: .ignored, reason: "无密码系统权限自动处理已暂停")
            } else if let reason = window.decision.rejection {
                activity?.finish(token: window.activityToken, outcome: .ignored, reason: "系统权限规则未接受：\(reason.rawValue)")
            }
        }
        defer {
            journal.observe(enabled: enabled, windows: windows.count, remaining: remaining,
                            providers: scanner.providerCount, trustedProviders: scanner.trustedProviderCount,
                            windowReadCodes: scanner.windowReadCodes)
            diagnosticsFailed = journal.persistenceFailed
        }
        guard enabled else { cancelCurrent(); return }
        seen.formIntersection(Set(windows.map(\.id)))
        for window in windows where window.decision.match == nil && !seen.contains(window.id) {
            seen.insert(window.id)
            journal.record(.rejected, category: nil, rejection: window.decision.rejection)
            status = "发现未匹配或需人工确认的系统窗口，已保留"
        }
        let eligible = windows.filter { $0.decision.match != nil && !gate.isSuppressed($0.id) &&
            activity?.blockingRule(for: $0.activityRequest, text: $0.context) == nil }
        let selected = PermissionPolicy.chooseWindow(eligible: eligible.map(\.id), current: pending?.id)
        let target = eligible.first { $0.id == selected }
        if let old = pending, let target, !old.matches(target) { cancelCurrent(); status = "权限窗口内容变化，本次已取消"; return }
        let idle = ProcessInfo.processInfo.systemUptime - lastInput >= 1
        switch gate.observe(target: target?.id, enabled: idle || remaining != nil, delay: delay,
                            now: ProcessInfo.processInfo.systemUptime, visible: Set(windows.map(\.id))) {
        case .idle: remaining = nil; pending = nil; category = nil
        case .countdown(let seconds):
            if let target { activity?.finish(token: target.activityToken, outcome: .waiting, reason: "倒计时中，尚未提交") }
            if remaining == nil { journal.record(.countdown, category: target?.category) }
            pending = target; remaining = seconds; category = target?.category
            status = "\(seconds) 秒后允许\(category?.label ?? "系统权限")"
        case .submit:
            if let target { submit(target) }
        }
    }
    func executeNow() {
        guard gate.submitNow() != nil, let pending else { return }
        submit(pending)
    }
    private func submit(_ original: PermissionWindow) {
        remaining = nil; pending = nil
        guard activity?.checkBlocked(token: original.activityToken, request: original.activityRequest, text: original.context) != true else {
            status = "命中黑名单，本次权限请求已忽略"; return
        }
        guard enabled, activity?.loadFailed != true, AXIsProcessTrusted(),
              let fresh = scanner.scan().first(where: { $0.id == original.id }), original.matches(fresh),
              let button = fresh.button, AX.bool(button, kAXEnabledAttribute), AX.actions(button).contains(kAXPressAction) else {
            activity?.finish(token: original.activityToken, outcome: .failed, reason: "确认前权限窗口已变化，未点击")
            journal.record(.failed, category: original.category); status = "确认前权限窗口已变化，未点击"; return
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            activity?.finish(token: original.activityToken, outcome: .failed, reason: "系统拒绝允许动作（AX \(result.rawValue)）")
            journal.record(.failed, category: original.category, code: result.rawValue)
            status = "系统拒绝自动允许，请手动处理；本窗口不会重试"; return
        }
        checkingResult = true
        activity?.finish(token: original.activityToken, outcome: .submitted, reason: "已发送允许，等待系统弹窗关闭")
        journal.record(.sent, category: original.category)
        status = "已发送允许，等待系统窗口关闭"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.checkingResult = false
            let remains = self.scanner.scan().contains { $0.id == original.id }
            self.activity?.finish(token: original.activityToken, outcome: remains ? .failed : .success,
                                  reason: remains ? "允许后窗口仍存在，已停止重试" : "自动允许后弹窗已关闭；原任务的业务结果需另行核对")
            self.journal.record(remains ? .stillVisible : .closed, category: original.category)
            self.status = remains ? "允许后窗口仍在，本窗口已停止重试" : "权限窗口已关闭，请以原任务结果为准"
            self.category = nil
        }
    }
}
