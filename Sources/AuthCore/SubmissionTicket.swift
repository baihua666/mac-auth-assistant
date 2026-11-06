import Foundation

/// A delayed confirmation may only run in the same uninterrupted operation.
public struct SubmissionTicket {
    private let generation: Int
    private let createdAt: TimeInterval

    public init(generation: Int, now: TimeInterval) {
        self.generation = generation
        createdAt = now
    }

    public func isValid(now: TimeInterval, generation: Int) -> Bool {
        now.isFinite && createdAt.isFinite && self.generation == generation
            && now >= createdAt && now - createdAt <= 2
    }
}
