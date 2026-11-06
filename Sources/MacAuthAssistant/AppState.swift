import AppKit
import ApplicationServices
import AuthCore
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var hasCredentials = false
    @Published private(set) var account = NSUserName()
    @Published private(set) var delay = 10
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published var status = "请先设置管理员账号和密码"
    @Published var remaining: Int?
    @Published var probeRunning = false

    let scanner = DialogScanner()
    let store: CredentialStore
    let loginItem: LoginItemController
    let permissions: PermissionAutomation
    let activity: ActivityHistory
    let validation = RuntimeValidation()
    let diagnostics = RuntimeDiagnostics()
    var gate = CountdownGate()
    var focusGate = FocusRecoveryGate()
    let focusController = DialogFocusController()
    var lastHumanInputAt = -Double.infinity
    var pending: DetectedDialog?
    var generation = 0
    var processing = false
    var awaitingResult = false
    var settingsVisible = false
    var suspended = false
    var unreadableNewWindows: Set<String> = []
    var showCountdown: (() -> Void)?
    var hideCountdown: (() -> Void)?
    var hideSettingsForValidation: (() -> Void)?
    var showSettingsAfterValidation: (() -> Void)?
    var showActivity: (() -> Void)?
    var showUpdates: (() -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let preferences: UserDefaults
    private let accessibilityCheck: () -> Bool

    init(store: CredentialStore = CredentialStore(), preferences: UserDefaults = .standard,
         accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() }, activity: ActivityHistory? = nil) {
        let activity = activity ?? ActivityHistory()
        self.activity = activity
        self.store = store
        self.loginItem = LoginItemController(preferences: preferences)
        self.permissions = PermissionAutomation(preferences: preferences, activity: activity)
        self.preferences = preferences
        self.accessibilityCheck = accessibilityCheck
        let saved = preferences.integer(forKey: "countdownSeconds")
        delay = (1...300).contains(saved) ? saved : 10
        refreshCredentials()
        if preferences.bool(forKey: "automaticProcessingEnabled") { setEnabled(true) }
    }

    func start() {
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspended = true; self?.cancelCurrent(message: "倒计时已因锁屏或休眠取消") }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspended = false }
            })
        }
    }

    func setEnabled(_ value: Bool) {
        cancelCurrent()
        accessibilityGranted = accessibilityCheck()
        guard !value || (hasCredentials && accessibilityGranted && !activity.loadFailed) else {
            status = activity.loadFailed ? "历史或黑名单无法读取，自动操作已暂停" : hasCredentials
                ? "当前安装版本的权限尚未生效；若系统中已开启，请移除旧条目后重新添加本工具"
                : "请先保存管理员凭据，或读取钥匙串中已保存的凭据"
            return
        }
        enabled = value
        preferences.set(value, forKey: "automaticProcessingEnabled")
        unreadableNewWindows.removeAll()
        if value { _ = scanner.scan() } // Existing hidden-value forms are not treated as newly empty.
        status = value ? "已开启，等待系统管理员验证弹窗" : "自动处理已暂停"
    }

    func setDelay(_ seconds: Int) {
        guard (1...300).contains(seconds) else { return }
        delay = seconds
        preferences.set(seconds, forKey: "countdownSeconds")
        cancelCurrent(message: "倒计时时长已更新")
    }

    func saveCredentials(account: String, password: String) -> Bool {
        setEnabled(false)
        do {
            let credentials = try Credentials(account: account, password: password)
            try store.save(credentials)
            guard let saved = try store.load(), saved.account == credentials.account,
                  saved.password == credentials.password else {
                throw CredentialStore.StoreError(status: errSecDecode)
            }
            self.account = saved.account
            hasCredentials = true
            status = "凭据已保存在本机钥匙串，请开启自动处理"
            return true
        } catch { hasCredentials = false; status = error.localizedDescription; return false }
    }

    func deleteCredentials() {
        setEnabled(false)
        do {
            try store.delete()
            hasCredentials = false
            status = "已删除本工具保存的管理员凭据"
        } catch { status = error.localizedDescription }
    }

    @discardableResult
    func restoreSavedCredentials() -> Bool {
        setEnabled(false)
        do {
            guard let saved = try store.load(allowInteraction: true) else {
                hasCredentials = false
                status = "钥匙串中尚未保存本工具的管理员凭据"
                return false
            }
            account = saved.account
            hasCredentials = true
            status = "已读取保存的凭据，请开启自动处理"
            return true
        } catch {
            hasCredentials = false
            status = error.localizedDescription
            return false
        }
    }

    private func refreshCredentials() {
        do {
            let credentials = try store.load()
            hasCredentials = credentials != nil
            if let credentials { account = credentials.account; status = "凭据已保存，自动处理尚未开启" }
        } catch { hasCredentials = false; status = error.localizedDescription }
    }

    func cancelCurrent(message: String? = nil) {
        if let pending { activity.finish(token: pending.activityToken, outcome: .ignored, reason: message ?? "本次自动处理已取消") }
        if remaining != nil { diagnostics.record(.submissionStopped, code: 7) }
        if let pending { unreadableNewWindows.remove(pending.id) }
        generation += 1
        gate.cancel()
        pending = nil
        remaining = nil
        hideCountdown?()
        if let message { status = message }
    }

    func executeImmediately() {
        if permissions.remaining != nil { permissions.executeNow(); return }
        guard let id = gate.submitNow(), let pending, pending.id == id else { return }
        performSubmission(pending)
    }

    func cancelVisibleCountdown() {
        if permissions.remaining != nil { permissions.cancelCurrent() }
        else { cancelCurrent(message: "本次已取消，系统弹窗保留供手动处理") }
    }

    func beginSystemValidation() {
        guard enabled, hasCredentials, AXIsProcessTrusted(), !probeRunning else {
            status = "请先开启自动处理，并确认凭据及辅助功能权限已就绪"
            return
        }
        guard scanner.scan().isEmpty else {
            status = "已有系统验证窗口，请先完成或取消该窗口，再开始本次自检"
            return
        }
        cancelCurrent()
        let prompt = validation.start()
        probeRunning = true
        hideSettingsForValidation?()
        status = "正在申请一次系统管理员验证；请等待倒计时，不要手动填写或确认"
        SystemAuthorizationProbe.run(prompt: prompt) { [weak self] code in
            guard let self else { return }
            self.validation.finish(status: code)
            self.probeRunning = false
            self.status = "真实自检：\(self.validation.evidence?.result.label ?? "无结果")（系统返回 \(code)）"
            self.showSettingsAfterValidation?()
        }
    }

    private func tick() {
        accessibilityGranted = AXIsProcessTrusted()
        guard !processing else {
            recordRuntime(dialogs: scanner.current, focused: scanner.current.first { scanner.isFocused($0) })
            return
        }
        let dialogs = scanner.scan()
        pauseBlacklistedCountdown(dialogs)
        permissions.tick(allowed: accessibilityGranted && !suspended && !activity.loadFailed && dialogs.isEmpty,
                         delay: delay, lastInput: lastHumanInputAt)
        let visible = Set(dialogs.map(\.id))
        let focused = recoverFocus(dialogs: dialogs, focused: dialogs.first { scanner.isFocused($0) })
        let ready = automationConditions.isReady
        defer { recordRuntime(dialogs: dialogs, focused: focused) }
        unreadableNewWindows.formIntersection(visible)
        if ready {
            for dialog in dialogs where dialog.isNewWindow && dialog.facts.passwordState == .unknown {
                unreadableNewWindows.insert(dialog.id)
            }
        }
        trackAdministrator(dialogs)
        if validation.active {
            validation.associate(dialogs)
            validation.observe(observation(dialogs: dialogs, focused: focused))
            if let focused, validation.matches(focused) { validation.record(.dialogSeen) }
        }
        if let old = pending, let focused, old.id == focused.id, !old.isSameForm(as: focused) {
            cancelCurrent(message: "窗口内容或账号已变化，本次自动处理已取消")
        }
        if let focused, let reason = rejection(for: focused), ready {
            cancelCurrent(message: reason)
        }
        let target = focused.flatMap { rejection(for: $0) == nil ? $0.id : nil }
        let event = gate.observe(target: target, enabled: ready, delay: delay,
                                 now: ProcessInfo.processInfo.systemUptime, visible: visible)
        switch event {
        case .idle:
            if remaining != nil { cancelCurrent(message: "本次自动处理已取消") }
        case .countdown(let seconds):
            if let focused { activity.finish(token: focused.activityToken, outcome: .waiting, reason: "倒计时中，尚未提交") }
            pending = focused
            remaining = seconds
            status = "\(seconds) 秒后填写管理员密码并确认"
            if let focused, validation.matches(focused) { validation.record(.countdown, seconds: seconds) }
            showCountdown?()
        case .submit(let id):
            guard let focused, focused.id == id else { cancelCurrent(); return }
            performSubmission(focused)
        }
    }

    func rejection(for dialog: DetectedDialog) -> String? {
        if activity.loadFailed { return "历史或黑名单无法读取，自动操作已暂停" }
        if let rule = activity.blockingRule(for: dialog.activityRequest, text: dialog.context) { return "命中黑名单：\(rule.name)" }
        return DialogPolicy.rejection(for: dialog.facts, allowUnreadableInput: unreadableNewWindows.contains(dialog.id))
    }
}
