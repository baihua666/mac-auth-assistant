import SwiftUI
import AppKit
import AuthCore

struct UpdateView: View {
    @ObservedObject var controller: UpdateController
    let permittedToInstall: () -> Bool
    @State private var confirmInstall = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("版本与更新").font(.title2.bold())
                    Text("当前版本 \(controller.current.label)")
                    Text("源码 \(controller.current.revision) · \(BuildIdentity.architecture)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("检查更新") { controller.check() }.disabled(controller.busy)
            }
            HStack {
                Toggle("自动检查更新", isOn: Binding(get: { controller.automatic }, set: controller.setAutomatic))
                Spacer()
                Picker("更新通道", selection: Binding(get: { controller.channel }, set: controller.setChannel)) {
                    ForEach(UpdateChannel.allCases, id: \.rawValue) { Text($0.label).tag($0) }
                }.frame(width: 240).disabled(controller.busy)
            }
            Text("自动检查每天最多一次，只检查版本；下载和安装由你发起。")
                .font(.caption).foregroundStyle(.secondary)
            if let date = controller.lastCheckedAt {
                Text("上次成功检查：\(date.formatted(date: .numeric, time: .standard))").font(.caption).foregroundStyle(.secondary)
            }
            if let result = controller.installResult { Text(result).font(.callout) }
            Divider()
            HStack(spacing: 10) {
                if controller.busy { ProgressView().controlSize(.small) }
                Text(controller.message).accessibilityIdentifier("updateStatus")
                Spacer()
                if controller.busy && controller.phase != .installing { Button("取消") { controller.cancel() } }
            }
            if controller.phase == .downloading {
                ProgressView(value: controller.progress).accessibilityLabel("安装包下载进度")
            }
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if controller.skipped != nil {
                HStack {
                    Text("已设置跳过版本").font(.caption).foregroundStyle(.secondary)
                    Button("恢复提醒") { controller.restoreSkipped() }.disabled(controller.busy)
                }
            }
            if controller.visibleReleases.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("发行记录").font(.headline)
                    Text("检查后会在这里显示公开发行版本和更新说明。暂无发行时可继续使用当前版本。")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HSplitView {
                    List(controller.visibleReleases, selection: $controller.selection) { release in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(release.version.description)\(release.prerelease ? " · 预览版" : "")").font(.headline)
                            if let date = release.publishedAt { Text(date.formatted(date: .numeric, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                            Text(release.build > 0 ? "构建 \(release.build)" : "暂无本机安装包").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(release.id)
                    }.frame(minWidth: 170, idealWidth: 190, maxWidth: 240).disabled(controller.busy)
                    if let release = controller.selected {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("\(release.version.description) 发行说明").font(.headline)
                                Text(release.notes.isEmpty ? "暂无发行说明" : release.notes).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(12)
                        }.frame(minWidth: 300)
                    }
                }.frame(minHeight: 200)
            }
            HStack {
                Button("GitHub 发行页") { open(controller.selected?.pageURL ?? URL(string: "https://github.com/\(AppRelease.repository)/releases")!) }
                Spacer()
                if controller.canDownload {
                    Button("跳过此版本") { controller.skipSelected() }
                    if controller.canInstall {
                        Button("安装并重启…") { confirmInstall = true }.buttonStyle(.borderedProminent)
                    } else {
                        Button("下载并校验") { controller.download() }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }.padding(24).frame(minWidth: 700, minHeight: 550)
        .confirmationDialog("安装更新并重启授权助手？已保存的凭据、设置、历史和黑名单会保留。", isPresented: $confirmInstall) {
            Button("安装并重启") {
                controller.install(permitted: permittedToInstall()) { NSApplication.shared.terminate(nil) }
            }
        }
    }
    private func open(_ url: URL) {
        guard AppRelease.isRepositoryURL(url, prefix: "releases") else { return }
        NSWorkspace.shared.open(url)
    }
}
