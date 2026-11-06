import Foundation

public struct FocusRecoveryGate {
    private var attempts: [String: Int] = [:]
    private var lastAttempt: [String: TimeInterval] = [:]
    public init() {}
    public func isExhausted(_ id: String) -> Bool { attempts[id, default: 0] >= 2 }
    public mutating func request(_ id: String, now: TimeInterval, lastInput: TimeInterval) -> Bool {
        guard now.isFinite, now - lastInput >= 1, attempts[id, default: 0] < 2,
              now - (lastAttempt[id] ?? -Double.infinity) >= 1 else { return false }
        attempts[id, default: 0] += 1
        lastAttempt[id] = now
        return true
    }
    public mutating func retain(visible: Set<String>) {
        attempts = attempts.filter { visible.contains($0.key) }
        lastAttempt = lastAttempt.filter { visible.contains($0.key) }
    }
}
