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
    @State private var editing: BlockRule?
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
            }
            if let selected {
                Text(selected.request.summary).font(.headline).textSelection(.enabled)
                Text(selected.reason).font(.callout).textSelection(.enabled)
                HStack {
                    Button("屏蔽同一请求…") { editing = BlockRule(exactRequest: selected.request) }
                        .disabled(selected.request.taskKey.isEmpty || history.loadFailed)
                    Text(selected.request.taskKey.isEmpty ? "旧诊断缺少任务标识，可在黑名单中新建类别或关键词规则。" : "精确屏蔽此请求，不影响同一软件的其它任务。")
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
        .sheet(item: $editing) { rule in RuleEditor(history: history, initial: rule) }
        .confirmationDialog("清空历史记录？黑名单规则会保留。", isPresented: $confirmClear) {
            Button("清空历史记录", role: .destructive) { history.clearRecords(); selection = nil }
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
