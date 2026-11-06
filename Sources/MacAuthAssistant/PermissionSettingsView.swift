import SwiftUI

struct PermissionSettingsView: View {
    @ObservedObject var controller: PermissionAutomation
    var body: some View {
        GroupBox("无密码系统权限") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("自动允许已识别的系统权限请求", isOn: Binding(get: { controller.enabled }, set: controller.setEnabled))
                Text("支持文件夹、本地网络、相机、麦克风、屏幕、定位、通讯录等系统请求。共用上方倒计时，将实际授予对应权限；有“允许一次”时优先选择。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(controller.status).font(.caption)
                if controller.diagnosticsFailed {
                    Text("权限处理诊断未能保存，请检查磁盘空间。")
                        .font(.caption).foregroundStyle(.orange)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}
