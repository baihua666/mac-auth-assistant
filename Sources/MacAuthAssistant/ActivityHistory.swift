import Foundation
import Combine
import AuthCore

@MainActor
final class ActivityHistory: ObservableObject {
    struct Document: Codable {
        var records: [ActivityRecord] = []
        var rules: [BlockRule] = []
        var legacyImported = false
    }
    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacAuthAssistant/activity.json")
    }
    @Published private(set) var records: [ActivityRecord] = []
    @Published private(set) var rules: [BlockRule] = []
    @Published private(set) var persistenceFailed = false
    @Published private(set) var loadFailed = false
    private let destination: URL?
    private var live: [String: UUID] = [:]
    private var legacyImported = false

    init(destination: URL? = nil) {
        self.destination = destination
        reload()
    }
    func reload() {
        guard let destination, FileManager.default.fileExists(atPath: destination.path) else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(Document.self, from: Data(contentsOf: destination))
            guard document.rules.allSatisfy(\.isValid) else { throw NSError(domain: "ActivityHistory", code: 2) }
            records = Array(document.records.prefix(1000)); rules = document.rules.filter(\.isValid)
            loadFailed = false; persistenceFailed = false; live = [:]
            legacyImported = document.legacyImported
            var interrupted = false
            for i in records.indices where !records[i].outcome.isTerminal {
                records[i].outcome = .ignored; records[i].reason = "上次运行中断，结果未验证"; interrupted = true
            }
            if interrupted { autosave() }
        } catch { loadFailed = true; persistenceFailed = true }
    }
    func observe(token: String, request: ActivityRequest, retryIgnored: Bool = false) {
        if let id = live[token], let old = records.first(where: { $0.id == id }), old.request == request,
           !(retryIgnored && old.outcome.isTerminal && old.outcome != .success) { return }
        let record = ActivityRecord(request: request)
        records.insert(record, at: 0); records = Array(records.prefix(1000)); live[token] = record.id
        autosave()
    }
    func finish(token: String, outcome: ActivityOutcome, reason: String, ruleID: UUID? = nil) {
        guard let id = live[token], let index = records.firstIndex(where: { $0.id == id }),
              !records[index].outcome.isTerminal else { return }
        guard records[index].outcome != outcome || records[index].reason != reason || records[index].ruleID != ruleID else { return }
        records[index].outcome = outcome; records[index].reason = reason
        records[index].ruleID = ruleID; records[index].updatedAt = Date()
        autosave()
    }
    func reconcile(kind: ActivityKind, visible: Set<String>) {
        for (token, id) in live where !visible.contains(token) {
            guard let record = records.first(where: { $0.id == id }), record.request.kind == kind else { continue }
            if record.outcome == .waiting { finish(token: token, outcome: .ignored, reason: "处理前弹窗已关闭或由用户处理") }
            if record.outcome != .submitted { live.removeValue(forKey: token) }
        }
    }
    func blockingRule(for request: ActivityRequest, text: String) -> BlockRule? {
        rules.first { $0.matches(request, text: text) }
    }
    func requestRule(for request: ActivityRequest) -> BlockRule? {
        guard !request.taskKey.isEmpty else { return nil }
        return rules.first { $0.exactTaskKey == request.taskKey && $0.kind == request.kind &&
            $0.category == request.category && $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    func isRequestBlocked(_ request: ActivityRequest) -> Bool { requestRule(for: request)?.enabled == true }
    func setRequestBlocked(_ request: ActivityRequest, blocked: Bool) throws {
        guard !loadFailed, !request.taskKey.isEmpty else {
            throw NSError(domain: "ActivityHistory", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "记录缺少任务信息或黑名单无法读取，未修改规则"])
        }
        let existing = requestRule(for: request)
        if existing == nil && !blocked { return }
        var rule = existing ?? BlockRule(exactRequest: request)
        if existing != nil && rule.enabled == blocked { return }
        rule.enabled = blocked
        try saveRule(rule)
    }
    @discardableResult
    func checkBlocked(token: String, request: ActivityRequest, text: String) -> Bool {
        if loadFailed {
            observe(token: token, request: request)
            finish(token: token, outcome: .ignored, reason: "历史与黑名单读取失败，自动操作已暂停")
            return true
        }
        guard let rule = blockingRule(for: request, text: text) else { return false }
        observe(token: token, request: request)
        finish(token: token, outcome: .ignored, reason: "命中黑名单：\(rule.name)", ruleID: rule.id)
        return true
    }
    func saveRule(_ rule: BlockRule) throws {
        guard rule.isValid else { throw NSError(domain: "ActivityHistory", code: 1, userInfo: [NSLocalizedDescriptionKey: "请输入规则名称及至少一个匹配条件"] ) }
        let previous = rules
        if let index = rules.firstIndex(where: { $0.id == rule.id || (rule.exactTaskKey != nil && $0.exactTaskKey == rule.exactTaskKey && $0.kind == rule.kind && $0.category == rule.category && $0.keyword == rule.keyword) }) {
            var saved = rule; saved.id = rules[index].id; rules[index] = saved
        }
        else { rules.append(rule) }
        do { try persist(); persistenceFailed = false } catch { rules = previous; persistenceFailed = true; throw error }
    }
    func setRuleEnabled(_ id: UUID, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = enabled; autosave()
    }
    func removeRule(_ id: UUID) { rules.removeAll { $0.id == id }; autosave() }
    func clearRecords() { records = []; live = [:]; autosave() }
    func retrySave() { autosave() }
    func importLegacyPermissions() {
        guard !legacyImported, !loadFailed, let destination else { return }
        struct Legacy: Decodable { let events: [PermissionEntry] }
        let path = destination.deletingLastPathComponent().appendingPathComponent("permissions.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: path), let legacy = try? decoder.decode(Legacy.self, from: data) {
            for event in legacy.events {
                let outcome: ActivityOutcome
                switch event.stage {
                case .closed: outcome = .success
                case .failed, .stillVisible: outcome = .failed
                case .cancelled, .rejected: outcome = .ignored
                default: continue
                }
                var record = ActivityRecord(request: ActivityRequest(kind: .permission, context: "", category: event.category),
                                            outcome: outcome, reason: "旧权限诊断导入（缺少应用和任务标识）：\(event.stage.rawValue)")
                record.updatedAt = event.at
                records.insert(record, at: 0)
            }
        }
        records = Array(records.prefix(1000)); legacyImported = true; autosave()
    }
    private func autosave() {
        do { try persist(); persistenceFailed = false } catch { persistenceFailed = true }
    }
    private func persist() throws {
        guard !loadFailed else { throw NSError(domain: "ActivityHistory", code: 3) }
        guard let destination else { return }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Document(records: records, rules: rules, legacyImported: legacyImported)).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
