import Foundation

/// What the town is waiting for next, kept in the store so a relaunch resumes where the
/// town stopped (requirements §3.4, §3.5, §3.7, §5). Its fields change as the town runs,
/// and the caps on them (at most your 3 latest posts pending) are the engine's rules,
/// so it is a plain record.
public struct Schedule: Sendable, Equatable {
    /// One response scene owed to one of your posts (requirements.md:227–:228).
    public struct PendingResponse: Sendable, Equatable {
        /// The post the response answers.
        public var post: EntityID<Post>
        /// When the response scene is due, in town time.
        public var dueAt: Date

        /// Creates a pending response.
        public init(post: EntityID<Post>, dueAt: Date) {
            self.post = post
            self.dueAt = dueAt
        }
    }

    /// When the next ordinary scene is due, in town time.
    public var nextOrdinarySceneDue: Date
    /// When the town last ran — where a pause is measured from (§3.7).
    public var lastRanAt: Date
    /// Response scenes still owed to your posts.
    public var pendingResponses: [PendingResponse]

    /// Creates a schedule.
    public init(
        nextOrdinarySceneDue: Date,
        lastRanAt: Date,
        pendingResponses: [PendingResponse] = [],
    ) {
        self.nextOrdinarySceneDue = nextOrdinarySceneDue
        self.lastRanAt = lastRanAt
        self.pendingResponses = pendingResponses
    }
}
