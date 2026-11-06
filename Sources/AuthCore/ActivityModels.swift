import Foundation
import CryptoKit

public enum ActivityKind: String, Codable, CaseIterable {
    case administrator, permission
    public var label: String { self == .administrator ? "管理员验证" : "系统权限" }
}
public enum ActivityOutcome: String, Codable, CaseIterable {
    case waiting, submitted, success, failed, ignored
    public var label: String {
        switch self {
        case .waiting: return "待处理"
        case .submitted: return "已提交"
        case .success: return "成功"
        case .failed: return "失败"
        case .ignored: return "忽略"
        }
    }
    public var isTerminal: Bool { self == .success || self == .failed || self == .ignored }
}
public struct ActivityRequest: Codable, Equatable {
    public let kind: ActivityKind
    public let category: PermissionCategory?
    public let application: String
    public let summary: String
    public let taskKey: String
    public init(kind: ActivityKind, context: String, category: PermissionCategory? = nil) {
        self.kind = kind; self.category = category
        let normalized = context.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        taskKey = context.isEmpty ? "" : SHA256.hash(data: Data((kind.rawValue + "|" + normalized).utf8)).map { String(format: "%02x", $0) }.joined()
        func capture(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: context, range: NSRange(context.startIndex..., in: context)),
                  let range = Range(match.range(at: 1), in: context) else { return nil }
            let value = context[range].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : String(value.prefix(80))
        }
        application = capture("Used by ([^\\n]+?) to ") ??
            capture("(?:allow|允许|允許)\\s*[“\\\"]([^”\\\"\\n]+)[”\\\"]") ??
            capture("[“\\\"]([^”\\\"\\n]+)[”\\\"]\\s*(?:想|请求|would|wants|is requesting|が|から)") ??
            capture("(?:^|\\n)([^\\n]{1,80}?) (?:would like|wants to|is trying|is requesting)") ?? "系统请求"
        if kind == .administrator, let action = capture("Used by [^\\n]+? to ([^\\n]{1,140})") {
            summary = "\(application) · \(action)"
        } else { summary = "\(application) · \(category?.label ?? kind.label)" }
    }
}
public struct ActivityRecord: Identifiable, Codable {
    public let id: UUID
    public let startedAt: Date
    public var updatedAt: Date
    public let request: ActivityRequest
    public var outcome: ActivityOutcome
    public var reason: String
    public var ruleID: UUID?
    public init(request: ActivityRequest, outcome: ActivityOutcome = .waiting, reason: String = "已发现请求") {
        id = UUID(); startedAt = Date(); updatedAt = startedAt
        self.request = request; self.outcome = outcome; self.reason = reason
    }
}
public struct BlockRule: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name: String
    public var enabled = true
    public var kind: ActivityKind?
    public var category: PermissionCategory?
    public var keyword: String
    public var exactTaskKey: String?
    public init(name: String, kind: ActivityKind? = nil, category: PermissionCategory? = nil, keyword: String = "") {
        self.name = name; self.kind = kind; self.category = category; self.keyword = keyword
    }
    public init(exactRequest: ActivityRequest) {
        name = exactRequest.summary; kind = exactRequest.kind; category = exactRequest.category; keyword = ""
        exactTaskKey = exactRequest.taskKey.isEmpty ? nil : exactRequest.taskKey
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (kind != nil || category != nil || !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exactTaskKey != nil)
    }
    public func matches(_ request: ActivityRequest, text: String) -> Bool {
        guard enabled, isValid, kind == nil || kind == request.kind, category == nil || category == request.category,
              exactTaskKey == nil || exactTaskKey == request.taskKey else { return false }
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return word.isEmpty || text.localizedCaseInsensitiveContains(word)
    }
}
