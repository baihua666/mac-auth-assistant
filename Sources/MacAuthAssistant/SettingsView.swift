import SwiftUI
import AppKit
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var account = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var validation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.system(size: 32)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac 授权助手").font(.title2.bold())
                    Text("系统管理员验证 · 倒计时自动填写与确认").foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("历史记录与黑名单…") { state.showActivity?() }
                Spacer()
                Button("版本与更新…") { state.showUpdates?() }
            }
            GroupBox("管理员凭据") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("管理员账号", text: $account).textContentType(.username)
                        .accessibilityLabel("管理员账号")
                    SecureField(state.hasCredentials ? "新密码（已有密码不会回显）" : "管理员密码", text: $password)
                        .textContentType(.password).accessibilityLabel("管理员密码")
                    SecureField("再次输入密码", text: $confirmation).accessibilityLabel("确认管理员密码")
                    HStack {
                        Button("保存到本机钥匙串") { save() }.disabled(password.isEmpty || account.isEmpty)
                        if state.hasCredentials {
                            Text("已保存：\(state.account)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("删除凭据", role: .destructive) { state.deleteCredentials() }
                        }
                    }
                    if !state.hasCredentials {
                        Button("读取已保存凭据") { state.restoreSavedCredentials() }
                    }
                    if !validation.isEmpty { Text(validation).font(.caption).foregroundStyle(.red) }
                    Text("密码仅保存在本机钥匙串，不上传，不写入日志或剪贴板。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).textFieldStyle(.roundedBorder)
            }
            GroupBox("自动处理") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("自动处理系统管理员密码验证", isOn: Binding(get: { state.enabled }, set: state.setEnabled))
                    Stepper(value: Binding(get: { state.delay }, set: state.setDelay), in: 1...300) {
                        Text("倒计时：\(state.delay) 秒")
                    }
                    LoginItemSettingsView(controller: state.loginItem)
                    Text("适用于各应用触发的可操作系统认证窗口。倒计时结束后将实际确认对应操作。此设置窗口保持打开也会检测。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            HStack {
                Image(systemName: state.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(state.accessibilityGranted ? .green : .orange)
                Text(state.accessibilityGranted ? "辅助功能权限已授予" : "需要手动授予辅助功能权限")
                Spacer()
                Button("权限设置…") { openAccessibilitySettings() }
            }.font(.callout)
            PermissionSettingsView(controller: state.permissions)
            GroupBox("真实系统自检") {
                VStack(alignment: .leading, spacing: 8) {
                    Button(state.probeRunning ? "自检进行中…" : "使用已保存凭据验证真实管理员弹窗") { state.beginSystemValidation() }
                        .disabled(!state.enabled || !state.hasCredentials || !state.accessibilityGranted || state.probeRunning)
                    Text("只申请一次管理员身份验证，不执行安装或修改设置。点击后请勿手动操作弹窗，等待自动流程结束。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let evidence = state.validation.evidence {
                        Text(evidence.result.label).font(.caption)
                    }
                    if state.validation.persistenceFailed {
                        Text("自检记录未能保存，请检查磁盘可用空间。结果不能据此交付。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Text(state.status).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .padding(10).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            Text("无法操作的系统窗口会提示手动处理。Apple Account、独立钥匙串或磁盘密码、开机和锁屏登录不使用这里的管理员密码。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(width: 540)
        .onAppear { account = state.account }
        .onDisappear { password = ""; confirmation = "" }
    }

    private func save() {
        guard password == confirmation else { validation = "两次输入的密码不一致"; return }
        validation = ""
        if state.saveCredentials(account: account, password: password) { password = ""; confirmation = "" }
    }

    private func openAccessibilitySettings() {
        // Target is Apple's System Settings accessibility privacy pane.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct CountdownView: View {
    @ObservedObject var state: AppState
    @ObservedObject var permissions: PermissionAutomation
    init(state: AppState) { self.state = state; self.permissions = state.permissions }
    private var isPermission: Bool { permissions.remaining != nil }

    var body: some View {
        VStack(spacing: 12) {
            Text(isPermission ? "即将允许系统权限请求" : "即将确认系统管理员授权").font(.headline)
            Text("\(permissions.remaining ?? state.remaining ?? 0)").font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
            Text(isPermission ? "秒后允许\(permissions.category?.label ?? "系统权限")" : "秒后填写密码并确认当前系统弹窗")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button("取消本次") { state.cancelVisibleCountdown() }
                Button("立即执行") { state.executeImmediately() }.buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 340, height: 210)
    }
}
