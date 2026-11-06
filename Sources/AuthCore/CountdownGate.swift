import Foundation

public enum CountdownEvent: Equatable {
    case idle
    case countdown(Int)
    case submit(String)
}

/// Uses monotonic time. Suppression lasts until the corresponding window is gone.
public struct CountdownGate {
    private var target: String?
    private var deadline: TimeInterval = 0
    private var lastObservation: TimeInterval?
    private var suppressed: Set<String> = []
    public private(set) var startedAt: TimeInterval?

    public init() {}

    public mutating func observe(target next: String?, enabled: Bool, delay: Int,
                                 now: TimeInterval, visible: Set<String>? = nil) -> CountdownEvent {
        let live = visible ?? Set(next.map { [$0] } ?? [])
        suppressed.formIntersection(live)
        defer { lastObservation = now }
        if target != nil, let previous = lastObservation,
           !now.isFinite || now < previous || now - previous > 2 {
            cancel()
            return .idle
        }
        guard enabled, (1...300).contains(delay), now.isFinite else {
            cancel()
            return .idle
        }
        if target != next { cancel() }
        guard let next, !suppressed.contains(next) else { return .idle }
        if target == nil {
            target = next
            startedAt = now
            deadline = now + Double(delay)
        }
        let remaining = Int(ceil(max(0, deadline - now)))
        if remaining == 0, let id = submitNow() { return .submit(id) }
        return .countdown(remaining)
    }

    public mutating func cancel() {
        if let target { suppressed.insert(target) }
        target = nil
        startedAt = nil
    }

    public func isSuppressed(_ id: String) -> Bool { suppressed.contains(id) }

    /// Filtering is reversible; explicit cancellation and completed submissions stay suppressed.
    @discardableResult
    public mutating func pauseIfBlocked(_ blocked: Set<String>) -> Bool {
        guard let target, blocked.contains(target) else { return false }
        pauseForFocusLoss()
        return true
    }

    public mutating func pauseForFocusLoss() {
        target = nil
        startedAt = nil
        lastObservation = nil
    }

    /// Global input callbacks can reach the main actor after a newer countdown starts.
    public mutating func cancelForInteraction(at timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite, let startedAt, timestamp >= startedAt else { return false }
        cancel()
        return true
    }

    public mutating func submitNow() -> String? {
        guard let id = target else { return nil }
        suppressed.insert(id)
        target = nil
        return id
    }
}
