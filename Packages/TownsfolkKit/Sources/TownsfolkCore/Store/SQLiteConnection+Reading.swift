import Foundation

/// A `posts` row, read before its tags are queried.
private struct PostRow {
    let id: UUID
    let author: UUID?
    let text: String
    let happenedAt: Date
    let replyTarget: UUID?
    let origin: Post.Origin?
    let sceneID: UUID?

    init(_ row: inout SQLiteRow) throws(TownStoreError) {
        id = try row.uuid()
        author = try row.optionalUUID()
        text = try row.text()
        happenedAt = try row.date()
        replyTarget = try row.optionalUUID()
        origin = try row.optionalText().map { code throws(TownStoreError) in
            try Post.Origin(code: code)
        }
        sceneID = try row.optionalUUID()
    }
}

/// An `interests` row, read before its source posts are queried.
private struct InterestRow {
    let id: UUID
    let term: String
    let firstMentionedAt: Date
    let lastMentionedAt: Date
    let mentions: Int

    init(_ row: inout SQLiteRow) throws(TownStoreError) {
        id = try row.uuid()
        term = try row.text()
        firstMentionedAt = try row.date()
        lastMentionedAt = try row.date()
        mentions = try row.count()
    }
}

/// A `residents` row, read before its child rows are queried.
private struct ResidentRow {
    let id: UUID
    let name: String
    let ageGroup: String
    let occupation: String
    let hobby: String
    let worry: String
    let personality: String
    let movedInAt: Date
    let movedOutAt: Date?

    init(_ row: inout SQLiteRow) throws(TownStoreError) {
        id = try row.uuid()
        name = try row.text()
        ageGroup = try row.text()
        occupation = try row.text()
        hobby = try row.text()
        worry = try row.text()
        personality = try row.text()
        movedInAt = try row.date()
        movedOutAt = row.optionalDate()
    }
}

/// Runs a Core value's initializer on stored fields, reporting a broken rule as
/// ``TownStoreError/rejectedRow(_:)``.
private func rejectingRow<Value>(
    _ make: () throws(TownValueError) -> Value,
) throws(TownStoreError) -> Value {
    do {
        return try make()
    } catch {
        throw .rejectedRow(error)
    }
}

/// Reads rows back into Core values through the values' own initializers, so a row that
/// breaks a rule surfaces as ``TownStoreError/rejectedRow(_:)`` rather than as a value
/// no other code could have built.
extension SQLiteConnection {
    private static func event(from row: inout SQLiteRow) throws(TownStoreError) -> TownEvent {
        let id = try TownEvent.ID(rawValue: row.uuid())
        let kind = try EventKindID(rawValue: row.text())
        let description = try row.text()
        let startsAt = try row.date()
        let endsAt = try row.date()
        let status = try TownEvent.Status(code: row.text())
        let related = try row.optionalUUID().map(Resident.ID.init(rawValue:))
        return try rejectingRow { () throws(TownValueError) in
            try TownEvent(
                id: id,
                kind: kind,
                description: description,
                startsAt: startsAt,
                endsAt: endsAt,
                status: status,
                relatedResident: related,
            )
        }
    }

    func town(tuning: Tuning) throws(TownStoreError) -> Town? {
        let places = try rows(
            "SELECT name FROM town_places ORDER BY position",
            [],
        ) { row throws(TownStoreError) in
            try row.text()
        }
        return try firstRow(
            "SELECT name, setting, founded_at FROM town",
            [],
        ) { row throws(TownStoreError) in
            let name = try row.text()
            let setting = try row.text()
            let foundedAt = try row.date()
            return try rejectingRow { () throws(TownValueError) in
                try Town(
                    name: name,
                    setting: setting,
                    places: places,
                    foundedAt: foundedAt,
                    tuning: tuning,
                )
            }
        }
    }

    func residents() throws(TownStoreError) -> [Resident] {
        let drafts = try rows(
            """
            SELECT id, name, age_group, occupation, hobby, worry, personality, moved_in_at,
                moved_out_at
            FROM residents ORDER BY moved_in_at, name COLLATE BINARY, id
            """,
            [],
        ) { row throws(TownStoreError) in
            try ResidentRow(&row)
        }
        var residents: [Resident] = []
        for draft in drafts {
            try residents.append(resident(from: draft))
        }
        return residents
    }

    func post(_ id: UUID, tuning: Tuning) throws(TownStoreError) -> Post? {
        let draft = try firstRow(
            """
            SELECT id, author_resident_id, text, happened_at, reply_target_id, origin, scene_id
            FROM posts WHERE id = ?
            """,
            [.id(id)],
        ) { row throws(TownStoreError) in
            try PostRow(&row)
        }
        return try draft.map { draft throws(TownStoreError) in
            try post(from: draft, tuning: tuning)
        }
    }

    func event(_ id: UUID) throws(TownStoreError) -> TownEvent? {
        try firstRow(
            """
            SELECT id, kind, description, starts_at, ends_at, status, related_resident_id
            FROM events WHERE id = ?
            """,
            [.id(id)],
            read: Self.event(from:),
        )
    }

    func ongoingEvents() throws(TownStoreError) -> [TownEvent] {
        try rows(
            """
            SELECT id, kind, description, starts_at, ends_at, status, related_resident_id
            FROM events WHERE status = ? ORDER BY starts_at, id
            """,
            [.text(TownEvent.Status.ongoing.code)],
            read: Self.event(from:),
        )
    }

    func includedInterests() throws(TownStoreError) -> [Interest] {
        let drafts = try rows(
            """
            SELECT id, term, first_mentioned_at, last_mentioned_at, mentions FROM interests
            WHERE excluded = 0 ORDER BY last_mentioned_at DESC, id DESC
            """,
            [],
        ) { row throws(TownStoreError) in
            try InterestRow(&row)
        }
        var interests: [Interest] = []
        for draft in drafts {
            try interests.append(interest(from: draft))
        }
        return interests
    }

    func schedule() throws(TownStoreError) -> Schedule? {
        let pending = try rows(
            "SELECT post_id, due_at FROM pending_responses ORDER BY due_at, rowid",
            [],
        ) { row throws(TownStoreError) in
            try Schedule.PendingResponse(post: Post.ID(rawValue: row.uuid()), dueAt: row.date())
        }
        return try firstRow(
            "SELECT next_ordinary_scene_due, last_ran_at FROM schedule",
            [],
        ) { row throws(TownStoreError) in
            try Schedule(
                nextOrdinarySceneDue: row.date(),
                lastRanAt: row.date(),
                pendingResponses: pending,
            )
        }
    }

    /// Non-excluded posts that happened from `start` to `end` inclusive, newest first.
    func includedPosts(
        from start: Date,
        through end: Date,
        limit: Int,
        tuning: Tuning,
    ) throws(TownStoreError) -> [Post] {
        let drafts = try rows(
            """
            SELECT id, author_resident_id, text, happened_at, reply_target_id, origin, scene_id
            FROM posts WHERE excluded = 0 AND happened_at >= ? AND happened_at <= ?
            ORDER BY happened_at DESC, id DESC LIMIT ?
            """,
            [.date(start), .date(end), .integer(Int64(limit))],
        ) { row throws(TownStoreError) in
            try PostRow(&row)
        }
        var posts: [Post] = []
        for draft in drafts {
            try posts.append(post(from: draft, tuning: tuning))
        }
        return posts
    }

    /// The topic tags of posts not excluded that happened from `start` through `end`,
    /// newest post first and in each post's order, each tag once.
    func includedTopicTags(from start: Date, through end: Date) throws(TownStoreError) -> [String] {
        let tags = try rows(
            """
            SELECT tags.tag FROM post_topic_tags AS tags
            JOIN posts ON posts.id = tags.post_id
            WHERE posts.excluded = 0 AND posts.happened_at >= ? AND posts.happened_at <= ?
            ORDER BY posts.happened_at DESC, posts.id DESC, tags.position
            """,
            [.date(start), .date(end)],
        ) { row throws(TownStoreError) in
            try row.text()
        }
        var seen: Set<String> = []
        return tags.filter { seen.insert($0).inserted }
    }

    private func resident(from draft: ResidentRow) throws(TownStoreError) -> Resident {
        let id = SQLValue.id(draft.id)
        let relationships = try rows(
            """
            SELECT other_resident_id, description FROM resident_relationships
            WHERE resident_id = ? ORDER BY position
            """,
            [id],
        ) { row throws(TownStoreError) in
            let other = try Resident.ID(rawValue: row.uuid())
            let description = try row.text()
            return try rejectingRow { () throws(TownValueError) in
                try Resident.Relationship(resident: other, description: description)
            }
        }
        let interests = try rows(
            "SELECT interest_id FROM resident_interests WHERE resident_id = ? ORDER BY position",
            [id],
        ) { row throws(TownStoreError) in
            try Interest.ID(rawValue: row.uuid())
        }
        return try rejectingRow { () throws(TownValueError) in
            try Resident(
                id: Resident.ID(rawValue: draft.id),
                name: draft.name,
                profile: Resident.Profile(
                    ageGroup: draft.ageGroup,
                    occupation: draft.occupation,
                    hobby: draft.hobby,
                    worry: draft.worry,
                    personality: draft.personality,
                ),
                movedInAt: draft.movedInAt,
                status: draft.movedOutAt == nil ? .living : .movedOut,
                movedOutAt: draft.movedOutAt,
                relationships: relationships,
                interests: interests,
            )
        }
    }

    private func post(from draft: PostRow, tuning: Tuning) throws(TownStoreError) -> Post {
        let tags = try rows(
            "SELECT tag FROM post_topic_tags WHERE post_id = ? ORDER BY position",
            [.id(draft.id)],
        ) { row throws(TownStoreError) in
            try row.text()
        }
        return try rejectingRow { () throws(TownValueError) in
            try Post(
                id: Post.ID(rawValue: draft.id),
                author: draft.author.map { .resident(Resident.ID(rawValue: $0)) } ?? .you,
                text: draft.text,
                happenedAt: draft.happenedAt,
                replyTarget: draft.replyTarget.map(Post.ID.init(rawValue:)),
                topicTags: tags,
                origin: draft.origin,
                sceneID: draft.sceneID.map(SceneID.init(rawValue:)),
                tuning: tuning,
            )
        }
    }

    private func interest(from draft: InterestRow) throws(TownStoreError) -> Interest {
        let sources = try rows(
            "SELECT post_id FROM interest_source_posts WHERE interest_id = ? ORDER BY position",
            [.id(draft.id)],
        ) { row throws(TownStoreError) in
            try Post.ID(rawValue: row.uuid())
        }
        return try rejectingRow { () throws(TownValueError) in
            try Interest(
                id: Interest.ID(rawValue: draft.id),
                term: draft.term,
                firstMentionedAt: draft.firstMentionedAt,
                lastMentionedAt: draft.lastMentionedAt,
                mentions: draft.mentions,
                sourcePosts: sources,
            )
        }
    }
}

extension Post.Origin {
    /// The origin stored as `code`.
    /// - Throws: ``TownStoreError/malformedRow`` for a code this build does not know.
    init(code: String) throws(TownStoreError) {
        guard let origin = Self.allCases.first(where: { $0.code == code }) else {
            throw .malformedRow
        }
        self = origin
    }
}

extension TownEvent.Status {
    /// The status stored as `code`.
    /// - Throws: ``TownStoreError/malformedRow`` for a code this build does not know.
    init(code: String) throws(TownStoreError) {
        switch code {
        case Self.ended.code:
            self = .ended

        case Self.ongoing.code:
            self = .ongoing

        default:
            throw .malformedRow
        }
    }
}
