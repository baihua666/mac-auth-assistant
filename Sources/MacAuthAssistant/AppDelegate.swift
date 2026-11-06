import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = AppState(activity: ActivityHistory(destination: ActivityHistory.defaultURL))
    private let updater = UpdateController()
    private var item: NSStatusItem!
    private var settings: NSWindow?
    private var activityWindow: NSWindow?
    private var updateWindow: NSWindow?
    private var panel: NSPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private var inputMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        state.activity.importLegacyPermissions()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Mac 授权助手")
        item.button?.toolTip = "Mac 授权助手"
        state.showCountdown = { [weak self] in self?.showPanel() }
        state.hideCountdown = { [weak self] in self?.panel?.orderOut(nil) }
        state.hideSettingsForValidation = { [weak self] in
            self?.state.settingsVisible = false
            self?.settings?.orderOut(nil)
        }
        state.showSettingsAfterValidation = { [weak self] in self?.openSettings() }
        state.showActivity = { [weak self] in self?.openActivity() }
        state.showUpdates = { [weak self] in self?.openUpdates() }
        updater.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenu() }
        }.store(in: &subscriptions)
        state.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenu() }
        }.store(in: &subscriptions)
        state.loginItem.$state.sink { [weak self] value in
            self?.state.diagnostics.recordLoginItem(value, errorCode: self?.state.loginItem.errorCode)
        }.store(in: &subscriptions)
        state.loginItem.configureOnLaunch()
        state.permissions.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenu() }
        }.store(in: &subscriptions)
        state.activity.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenu() }
        }.store(in: &subscriptions)
        state.permissions.$remaining.sink { [weak self] value in
            DispatchQueue.main.async {
                guard let self, self.state.remaining == nil else { return }
                if value != nil { self.showPanel() } else { self.panel?.orderOut(nil) }
            }
        }.store(in: &subscriptions)
        // Observe human interaction without retaining any key contents.
        inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard !PasswordKeyboardEvents.isOwn(event.cgEvent) else { return }
            let timestamp = event.timestamp
            let isKeyboard = event.type == .keyDown
            let location = event.cgEvent?.location
            Task { @MainActor in
                if self?.state.validation.active == true { self?.state.validation.record(.manualInteraction) }
                self?.state.handleGlobalInput(at: timestamp, isKeyboard: isKeyboard, location: location)
            }
        }
        updateMenu()
        state.start()
        updater.start()
    }

    private func setupMainMenu() {
        let main = NSMenu()
        let application = NSMenuItem()
        let appMenu = NSMenu(title: "Mac 授权助手")
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        let history = NSMenuItem(title: "历史记录与黑名单…", action: #selector(openActivity), keyEquivalent: "")
        history.target = self
        appMenu.addItem(history)
        let updates = NSMenuItem(title: "版本与更新…", action: #selector(openUpdates), keyEquivalent: "")
        updates.target = self; appMenu.addItem(updates)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出授权助手", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        application.submenu = appMenu
        main.addItem(application)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"),
                                     ("拷贝", #selector(NSText.copy(_:)), "c"),
                                     ("粘贴", #selector(NSText.paste(_:)), "v"),
                                     ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        edit.submenu = editMenu
        main.addItem(edit)
        NSApplication.shared.mainMenu = main
    }

    private func updateMenu() {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "Mac 授权助手 \(updater.current.label)", action: nil, keyEquivalent: "")
        menu.addItem(heading)
        if state.activity.loadFailed {
            menu.addItem(NSMenuItem(title: "历史或黑名单读取失败，自动操作已暂停", action: nil, keyEquivalent: ""))
        } else if state.activity.persistenceFailed {
            menu.addItem(NSMenuItem(title: "记录或规则保存失败，请查看历史与黑名单", action: nil, keyEquivalent: ""))
        }
        let status = NSMenuItem(title: state.status, action: nil, keyEquivalent: "")
        menu.addItem(status)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "自动处理系统管理员验证", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = state.enabled ? .on : .off
        menu.addItem(toggle)
        let permissions = NSMenuItem(title: "自动允许无密码系统权限", action: #selector(togglePermissions), keyEquivalent: "")
        permissions.target = self
        permissions.state = state.permissions.enabled ? .on : .off
        menu.addItem(permissions)
        menu.addItem(NSMenuItem(title: state.permissions.status, action: nil, keyEquivalent: ""))
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let activity = NSMenuItem(title: "历史记录与黑名单…", action: #selector(openActivity), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)
        let updates = NSMenuItem(title: updater.latest.map { "发现新版本 \($0.version)…" } ?? "版本与更新…", action: #selector(openUpdates), keyEquivalent: "")
        updates.target = self; menu.addItem(updates)
        let pause = NSMenuItem(title: "取消本次倒计时", action: #selector(cancelCountdown), keyEquivalent: "")
        pause.target = self
        pause.isEnabled = state.remaining != nil || state.permissions.remaining != nil
        menu.addItem(pause)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出授权助手", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        item.button?.appearsDisabled = state.activity.loadFailed || (!state.enabled && !state.permissions.enabled)
    }

    @objc private func toggleEnabled() { state.setEnabled(!state.enabled) }
    @objc private func openUpdates() {
        if updateWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 610),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Mac 授权助手 — 版本与更新"
            window.contentView = NSHostingView(rootView: UpdateView(controller: updater, permittedToInstall: { [weak self] in
                guard let self else { return false }
                return !self.state.processing && !self.state.awaitingResult && !self.state.probeRunning &&
                    self.state.remaining == nil && !self.state.permissions.isProcessing
            }))
            window.isReleasedWhenClosed = false; window.center(); updateWindow = window
        }
        updateWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    @objc private func openActivity() {
        if activityWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Mac 授权助手 — 历史记录与黑名单"
            window.contentView = NSHostingView(rootView: ActivityView(history: state.activity))
            window.isReleasedWhenClosed = false; window.center(); activityWindow = window
        }
        activityWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    @objc private func togglePermissions() { state.permissions.setEnabled(!state.permissions.enabled) }
    @objc private func cancelCountdown() { state.cancelVisibleCountdown() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func openSettings() {
        state.settingsVisible = true
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 850),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Mac 授权助手 — 设置"
            window.contentView = NSHostingView(rootView: ScrollView { SettingsView(state: state) })
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settings = window
        }
        settings?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settings {
            state.settingsVisible = false
        }
    }

    private func showPanel() {
        if panel == nil {
            let window = CountdownPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 235),
                                        styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                                        backing: .buffered, defer: false)
            window.title = "系统授权倒计时"
            window.titlebarAppearsTransparent = true
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: CountdownView(state: state))
            panel = window
        }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: frame.maxX - 364, y: frame.minY + 24))
        }
        panel?.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.cancelCurrent()
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
    }
}

private final class CountdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
