import Foundation

/// The reads a scene is built from (requirements §3.8). Each throws
/// ``TownStoreError/closed`` after ``TownStore/deleteEverything()``, and
/// ``TownStoreError/malformedRow`` or ``TownStoreError/rejectedRow(_:)`` for a stored row
/// that no longer reads back as its Core value.
extension TownStore {
    private static let attosecondsPerSecond = 1e18

    /// The town, or `nil` before founding.
    public func town() throws(TownStoreError) -> Town? {
        try liveConnection().town(tuning: tuning)
    }

    /// Every resident, living and moved out, in the order they moved in. Past residents
    /// are kept so no one like them is invented again.
    public func residents() throws(TownStoreError) -> [Resident] {
        try liveConnection().residents()
    }

    /// The stored post with `id` — a reply's quote — or `nil`.
    public func post(_ id: Post.ID) throws(TownStoreError) -> Post? {
        try liveConnection().post(id.rawValue, tuning: tuning)
    }

    /// Events still going on, earliest first.
    public func ongoingEvents() throws(TownStoreError) -> [TownEvent] {
        try liveConnection().ongoingEvents()
    }

    /// The names you brought up that are not excluded from later contexts, most recently
    /// mentioned first.
    public func interests() throws(TownStoreError) -> [Interest] {
        try liveConnection().includedInterests()
    }

    /// The schedule, its pending responses soonest first, or `nil` before founding.
    public func schedule() throws(TownStoreError) -> Schedule? {
        try liveConnection().schedule()
    }

    /// The recent window a scene's context is drawn from: posts not excluded that
    /// happened within `tuning.generation.recentContextWindow` (24 hours) at or before
    /// `date`, newest first, at most `limit` of them (requirements §3.8).
    /// - Throws: ``TownStoreError/invalidLimit(_:)`` for a limit below 1.
    public func recentPosts(before date: Date, limit: Int) throws(TownStoreError) -> [Post] {
        guard limit >= 1 else {
            throw .invalidLimit(limit)
        }
        let window = tuning.generation.recentContextWindow.components
        let seconds = Double(window.seconds) + Double(window.attoseconds) / Self
            .attosecondsPerSecond
        return try liveConnection().includedPosts(
            from: date.addingTimeInterval(-seconds),
            through: date,
            limit: limit,
            tuning: tuning,
        )
    }
}
