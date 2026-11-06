import SwiftUI
import AuthCore

struct ActivityView: View {
    @ObservedObject var history: ActivityHistory
    var body: some View {
        VStack(spacing: 8) {
            if history.loadFailed {
                HStack {
                    Text("历史或黑名单无法读取，自动操作已暂停，原文件已保留。")
                    Button("重新读取") { history.reload() }
                }.foregroundStyle(.red).padding(8)
            } else if history.persistenceFailed {
                HStack {
                    Text("保存失败，当前变更可能无法在重启后保留。")
                    Button("重试保存") { history.retrySave() }
                }.foregroundStyle(.orange).padding(8)
            }
            TabView {
                HistoryTab(history: history).tabItem { Text("历史记录") }
                BlockRulesTab(history: history).tabItem { Text("黑名单") }
            }
        }.padding(12).frame(minWidth: 900, minHeight: 580)
    }
}

private struct HistoryTab: View {
    @ObservedObject var history: ActivityHistory
    @State private var search = ""
    @State private var outcome = "all"
    @State private var kind = "all"
    @State private var selection: UUID?
    @State private var actionMessage = ""
    @State private var actionError = ""
    @State private var confirmClear = false
    private var selected: ActivityRecord? { history.records.first { $0.id == selection } }
    private var rows: [ActivityRecord] {
        history.records.filter {
            (outcome == "all" || $0.outcome.rawValue == outcome) && (kind == "all" || $0.request.kind.rawValue == kind) &&
                (search.isEmpty || ($0.request.summary + " " + $0.reason).localizedCaseInsensitiveContains(search))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("搜索任务或原因", text: $search).textFieldStyle(.roundedBorder)
                Picker("状态", selection: $outcome) {
                    Text("全部状态").tag("all")
                    ForEach(ActivityOutcome.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }.frame(width: 180)
                Picker("类型", selection: $kind) {
                    Text("全部类型").tag("all")
                    ForEach(ActivityKind.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }.frame(width: 180)
            }
            Table(rows, selection: $selection) {
                TableColumn("时间") { Text($0.updatedAt.formatted(date: .numeric, time: .standard)) }.width(min: 145, ideal: 165)
                TableColumn("类型") { Text($0.request.kind.label) }.width(90)
                TableColumn("任务") { Text($0.request.summary).lineLimit(2) }
                TableColumn("结果") { Text($0.outcome.label).foregroundStyle(color($0.outcome)) }.width(70)
                TableColumn("黑名单") { record in blacklistAction(record) }.width(150)
            }
            if !actionError.isEmpty {
                Label(actionError, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
            } else if !actionMessage.isEmpty {
                Text(actionMessage).font(.callout).foregroundStyle(.secondary)
            }
            if let selected {
                Text(selected.request.summary).font(.headline).textSelection(.enabled)
                Text(selected.reason).font(.callout).textSelection(.enabled)
                HStack {
                    blacklistAction(selected)
                    Text(selected.request.taskKey.isEmpty ? "旧诊断缺少任务标识，无法准确屏蔽；新记录可直接加入。" : "一键屏蔽同一请求；移出仅取消此项屏蔽，其它规则仍生效。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("保留最近 1000 条；成功表示自动确认后弹窗关闭，原任务的业务结果需另行核对。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清空历史…") { confirmClear = true }.disabled(history.loadFailed)
            }
        }.padding(12)
        .confirmationDialog("清空历史记录？黑名单规则会保留。", isPresented: $confirmClear) {
            Button("清空历史记录", role: .destructive) { history.clearRecords(); selection = nil }
        }
    }
    @ViewBuilder
    private func blacklistAction(_ record: ActivityRecord) -> some View {
        if record.request.taskKey.isEmpty {
            Text("缺少任务信息").font(.caption).foregroundStyle(.secondary)
        } else if history.isRequestBlocked(record.request) {
            HStack(spacing: 8) {
                Label("已加入", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                Button("移出") { changeBlacklist(record, blocked: false) }
                    .buttonStyle(.borderless).disabled(history.loadFailed)
                    .accessibilityLabel("将\(record.request.summary)移出黑名单")
                    .help("取消对此请求的精确屏蔽，其它黑名单规则仍生效")
            }
        } else {
            Button("加入黑名单") { changeBlacklist(record, blocked: true) }
                .buttonStyle(.bordered).controlSize(.small).disabled(history.loadFailed)
                .accessibilityLabel("将\(record.request.summary)加入黑名单")
                .help("立即保存，不再自动处理同一请求，无需填写规则")
        }
    }
    private func changeBlacklist(_ record: ActivityRecord, blocked: Bool) {
        actionError = ""; actionMessage = ""; selection = record.id
        do {
            try history.setRequestBlocked(record.request, blocked: blocked)
            actionMessage = blocked ? "已加入黑名单，后续相同请求将被忽略。" : "已移出此请求的黑名单；其它匹配规则仍生效。"
        } catch {
            actionError = "黑名单保存失败，未更改规则。请检查磁盘空间和文件权限后重试。"
        }
    }
    private func color(_ outcome: ActivityOutcome) -> Color {
        switch outcome {
        case .success: return .green
        case .failed: return .red
        case .ignored: return .secondary
        case .waiting: return .blue
        case .submitted: return .orange
        }
    }
}
