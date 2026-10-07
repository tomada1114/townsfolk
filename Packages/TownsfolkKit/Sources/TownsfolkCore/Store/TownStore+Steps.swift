import Foundation

/// Every step of the town, each one transaction, and the records the steps that write
/// more than one thing take (requirements §5, `docs/architecture.md` › Persistence). The
/// records are plain: the rules that fill them belong to the engine and the writer, and
/// every value inside has already been checked by its own initializer. A step that throws has been
/// rolled back whole and announced nothing;
/// one that returns is committed and announced on ``TownStore/changes()``. Each throws
/// ``TownStoreError/closed`` after ``TownStore/deleteEverything()``, and
/// ``TownStoreError/statementFailed(code:)`` when SQLite refuses it — a post replying to,
/// or a row pointing at, something not stored is a foreign-key failure (`787`).
extension TownStore {
    /// One scene: the 1–3 posts one model call wrote, and what changes with them.
    public struct SceneStep: Sendable, Equatable {
        /// The scene's posts, in order. A reply may point at an earlier post of the same
        /// scene or at any stored post.
        public var posts: [Post]
        /// Names you brought up that the scene recorded or touched: each is stored new or
        /// replaces the stored one with its id, sources included. An excluded interest
        /// stays excluded.
        public var interests: [Interest]
        /// The pending response this scene delivers, removed if it is still pending.
        public var deliveredResponse: Schedule.PendingResponse?
        /// When the next ordinary scene is due; `nil` leaves it as it was.
        public var nextOrdinarySceneDue: Date?

        /// Creates a scene step.
        public init(
            posts: [Post],
            interests: [Interest] = [],
            deliveredResponse: Schedule.PendingResponse? = nil,
            nextOrdinarySceneDue: Date? = nil,
        ) {
            self.posts = posts
            self.interests = interests
            self.deliveredResponse = deliveredResponse
            self.nextOrdinarySceneDue = nextOrdinarySceneDue
        }
    }

    /// A founded town, written only once all of its generation succeeded (requirements
    /// §3.1, `docs/architecture.md` › Persistence).
    public struct FoundingStep: Sendable, Equatable {
        /// The town.
        public var town: Town
        /// Its first residents.
        public var residents: [Resident]
        /// The "You moved to {town}." event, the timeline's first row.
        public var foundingEvent: TownEvent
        /// The schedule the town starts with.
        public var schedule: Schedule
        /// The scene written at once, so the timeline is never empty.
        public var firstScene: SceneStep

        /// Creates a founding step.
        public init(
            town: Town,
            residents: [Resident],
            foundingEvent: TownEvent,
            schedule: Schedule,
            firstScene: SceneStep,
        ) {
            self.town = town
            self.residents = residents
            self.foundingEvent = foundingEvent
            self.schedule = schedule
            self.firstScene = firstScene
        }
    }

    /// A resident moving in or out, with the event that records it (requirements §3.6).
    public struct MoveStep: Sendable, Equatable {
        /// The resident as they are after the move: a newcomer, with any interest they
        /// start with already stored, or a resident now moved out. Stored new, or
        /// replacing the stored resident with its id.
        public var resident: Resident
        /// The move-in or move-out event.
        public var event: TownEvent

        /// Creates a move step.
        public init(resident: Resident, event: TownEvent) {
            self.resident = resident
            self.event = event
        }
    }

    /// Stores a founded town: the town, its residents, the founding event, the schedule,
    /// and the first scene. A town that already exists is refused (`1555`): moving away
    /// deletes it first.
    ///
    /// Checked for cancellation here, inside the store, as ``storeScene(_:)`` is: a call
    /// queued behind another step still runs after the caller's task was cancelled, and a
    /// founding cancelled midway keeps nothing (requirements.md:148).
    /// - Throws: ``TownStoreError/cancelled`` when the calling task was cancelled before
    ///   the transaction began; nothing is written.
    public func found(_ founding: FoundingStep) throws(TownStoreError) {
        guard !Task.isCancelled else {
            throw .cancelled
        }
        try commit(.founded) { connection throws(TownStoreError) in
            try connection.insert(founding.town)
            for resident in founding.residents {
                try connection.upsert(resident)
            }
            try connection.insert(founding.foundingEvent)
            try connection.insert(founding.schedule)
            try connection.insert(founding.firstScene)
        }
    }

    /// Stores one scene: its posts with their tags, the interests it touched, the pending
    /// response it delivers, and the next ordinary scene's due time.
    ///
    /// A scene is checked for cancellation here, inside the store, because a call queued
    /// behind another step still runs after the caller's task was cancelled.
    /// - Throws: ``TownStoreError/cancelled`` when the calling task was cancelled before
    ///   the transaction began; nothing is written.
    public func storeScene(_ scene: SceneStep) throws(TownStoreError) {
        guard !Task.isCancelled else {
            throw .cancelled
        }
        let change = TownStoreChange.sceneStored(posts: scene.posts.map(\.id))
        try commit(change) { connection throws(TownStoreError) in
            try connection.insert(scene)
        }
    }

    /// Moves the next ordinary scene's due time alone — a skipped turn.
    /// - Throws: ``TownStoreError/notFound`` before a town is founded.
    public func setNextOrdinarySceneDue(_ due: Date) throws(TownStoreError) {
        try commit(.nextOrdinarySceneDueChanged) { connection throws(TownStoreError) in
            try connection.setNextOrdinarySceneDue(due)
        }
    }

    /// Stores your post at once, alone; its responses are scheduled by a later step
    /// (`docs/architecture.md` › Core flows).
    public func storeYourPost(_ post: Post) throws(TownStoreError) {
        try commit(.yourPostStored(post.id)) { connection throws(TownStoreError) in
            try connection.insert(post)
        }
    }

    /// Changes the responses still owed to your posts: drops every one owed to the posts
    /// in `posts`, then adds `responses` — so a new post's schedule and the oldest one it
    /// displaces change together.
    public func updatePendingResponses(
        adding responses: [Schedule.PendingResponse],
        droppingFor posts: [Post.ID] = [],
    ) throws(TownStoreError) {
        try commit(.pendingResponsesChanged) { connection throws(TownStoreError) in
            for post in posts {
                try connection.run(
                    "DELETE FROM pending_responses WHERE post_id = ?",
                    [.id(post.rawValue)],
                )
            }
            try connection.insert(responses)
        }
    }

    /// Stores an event that starts.
    public func startEvent(_ event: TownEvent) throws(TownStoreError) {
        try commit(.eventStarted(event.id)) { connection throws(TownStoreError) in
            try connection.insert(event)
        }
    }

    /// Marks a stored event ended; it stays in the log as the town's history.
    /// - Throws: ``TownStoreError/notFound`` for an event not stored.
    public func endEvent(_ id: TownEvent.ID) throws(TownStoreError) {
        try commit(.eventEnded(id)) { connection throws(TownStoreError) in
            try connection.requireChange(
                connection.run(
                    "UPDATE events SET status = ? WHERE id = ?",
                    [.text(TownEvent.Status.ended.code), .id(id.rawValue)],
                ),
            )
        }
    }

    /// Stores a move: the resident as they are afterwards, with the event recording it.
    public func recordMove(_ move: MoveStep) throws(TownStoreError) {
        try commit(.moveRecorded(move.resident.id)) { connection throws(TownStoreError) in
            try connection.upsert(move.resident)
            try connection.insert(move.event)
        }
    }

    /// Records when the town last ran, where the next pause is measured from.
    /// - Throws: ``TownStoreError/notFound`` before a town is founded.
    public func setLastRan(_ date: Date) throws(TownStoreError) {
        try commit(.lastRanChanged) { connection throws(TownStoreError) in
            try connection.requireChange(
                connection.run("UPDATE schedule SET last_ran_at = ?", [.date(date)]),
            )
        }
    }

    /// Leaves a post out of later contexts; the timeline still shows it (requirements
    /// §3.11).
    /// - Throws: ``TownStoreError/notFound`` for a post not stored.
    public func excludePost(_ id: Post.ID) throws(TownStoreError) {
        try commit(.postExcluded(id)) { connection throws(TownStoreError) in
            try connection.requireChange(
                connection.run("UPDATE posts SET excluded = 1 WHERE id = ?", [.id(id.rawValue)]),
            )
        }
    }

    /// Leaves a name you brought up out of later contexts (requirements §3.11).
    /// - Throws: ``TownStoreError/notFound`` for an interest not stored.
    public func excludeInterest(_ id: Interest.ID) throws(TownStoreError) {
        try commit(.interestExcluded(id)) { connection throws(TownStoreError) in
            try connection.requireChange(
                connection.run(
                    "UPDATE interests SET excluded = 1 WHERE id = ?",
                    [.id(id.rawValue)],
                ),
            )
        }
    }

    /// Runs `body` as one transaction and, once it commits, announces `change`.
    func commit(
        _ change: TownStoreChange,
        _ body: (SQLiteConnection) throws(TownStoreError) -> Void,
    ) throws(TownStoreError) {
        let live = try liveConnection()
        try live.transaction { () throws(TownStoreError) in
            try body(live)
        }
        announce(change)
    }
}
