import SwiftUI

struct LoginItemSettingsView: View {
    @ObservedObject var controller: LoginItemController
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("登录后自动启动", isOn: Binding(get: { controller.isRequested }, set: controller.setEnabled))
            Text("启动后仅在菜单栏后台运行，自动恢复已保存的设置。")
                .font(.caption).foregroundStyle(.secondary)
            Text(controller.state.label).font(.caption)
            if let error = controller.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            if controller.state == .requiresApproval {
                Button("打开系统登录项设置…") { controller.openSystemSettings() }
            }
        }.onAppear { controller.refresh() }
    }
}
