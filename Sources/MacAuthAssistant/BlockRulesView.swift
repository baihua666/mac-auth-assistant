import SwiftUI
import AuthCore

struct BlockRulesTab: View {
    @ObservedObject var history: ActivityHistory
    @State private var editing: BlockRule?
    @State private var selection: UUID?
    @State private var search = ""
    @State private var deleting: BlockRule?
    private var selected: BlockRule? { history.rules.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("搜索规则名称或关键词", text: $search).textFieldStyle(.roundedBorder)
                Button("新建规则…") { editing = BlockRule(name: "新规则") }.disabled(history.loadFailed)
            }
            Table(history.rules.filter { search.isEmpty || ($0.name + $0.keyword).localizedCaseInsensitiveContains(search) }, selection: $selection) {
                TableColumn("启用") { rule in
                    Toggle("", isOn: Binding(get: { rule.enabled }, set: { history.setRuleEnabled(rule.id, enabled: $0) }))
                        .labelsHidden().disabled(history.loadFailed)
                }.width(55)
                TableColumn("规则名称", value: \.name)
                TableColumn("匹配类型") { Text($0.kind?.label ?? "全部类型") }.width(100)
                TableColumn("权限类别") { Text($0.category?.label ?? "全部类别") }.width(120)
                TableColumn("匹配方式") { Text($0.exactTaskKey == nil ? ($0.keyword.isEmpty ? "类型/类别" : $0.keyword) : "同一请求") }
            }
            HStack {
                Button("编辑…") { editing = selected }.disabled(selected == nil || history.loadFailed)
                Button("删除…") { deleting = selected }.disabled(selected == nil || history.loadFailed)
                Spacer()
                Text("同一规则内条件同时满足才忽略；多个规则中任意一条命中即可。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("规则保存后对后续自动操作生效，不撤销已经授予的权限；已取消或已提交的同一窗口不会自动重试。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12)
        .sheet(item: $editing) { rule in RuleEditor(history: history, initial: rule) }
        .confirmationDialog("删除所选黑名单规则？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除规则", role: .destructive) { if let deleting { history.removeRule(deleting.id) }; deleting = nil }
        }
    }
}

struct RuleEditor: View {
    @ObservedObject var history: ActivityHistory
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BlockRule
    @State private var error = ""
    private let originalKey: String?
    init(history: ActivityHistory, initial: BlockRule) {
        self.history = history; _draft = State(initialValue: initial); originalKey = initial.exactTaskKey
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("黑名单规则").font(.title2)
            Form {
                TextField("规则名称", text: $draft.name)
                Toggle("启用规则", isOn: $draft.enabled)
                Picker("处理类型", selection: Binding(get: { draft.kind?.rawValue ?? "all" }, set: { draft.kind = ActivityKind(rawValue: $0); if draft.kind == .administrator { draft.category = nil } })) {
                    Text("全部类型").tag("all")
                    ForEach(ActivityKind.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                if draft.kind != .administrator {
                    Picker("权限类别", selection: Binding(get: { draft.category?.rawValue ?? "all" }, set: { draft.category = PermissionCategory(rawValue: $0) })) {
                        Text("全部类别").tag("all")
                        ForEach(PermissionCategory.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                }
                TextField("任务/应用关键词（可选，不区分大小写）", text: $draft.keyword)
                if originalKey != nil {
                    Toggle("仅匹配历史中的同一请求", isOn: Binding(get: { draft.exactTaskKey != nil }, set: { draft.exactTaskKey = $0 ? originalKey : nil }))
                }
            }
            Text("关键词匹配当前弹窗的任务文字；历史只保留摘要。至少选择一种类型、类别、关键词或同一请求条件。")
                .font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    do { try history.saveRule(draft); dismiss() } catch let saveError { error = saveError.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(!draft.isValid || history.loadFailed)
            }
        }.padding(24).frame(width: 520)
    }
}
