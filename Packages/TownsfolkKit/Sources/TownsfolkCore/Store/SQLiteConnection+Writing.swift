import Foundation

/// The statements each step is made of. None opens a transaction: the step that calls
/// them does (``TownStore/commit(_:_:)``).
extension SQLiteConnection {
    func insert(_ town: Town) throws(TownStoreError) {
        try run(
            "INSERT INTO town (id, name, setting, founded_at) VALUES (1, ?, ?, ?)",
            [.text(town.name), .text(town.setting), .date(town.foundedAt)],
        )
        for (position, place) in town.places.enumerated() {
            try run(
                "INSERT INTO town_places (position, name) VALUES (?, ?)",
                [.integer(Int64(position)), .text(place)],
            )
        }
    }

    /// Stores `resident` new, or replaces the stored resident with its id — the row and
    /// its relationships and interests.
    func upsert(_ resident: Resident) throws(TownStoreError) {
        let profile = resident.profile
        try run(
            """
            INSERT INTO residents (id, name, age_group, occupation, hobby, worry, personality,
                moved_in_at, moved_out_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET name = excluded.name,
                age_group = excluded.age_group, occupation = excluded.occupation,
                hobby = excluded.hobby, worry = excluded.worry,
                personality = excluded.personality, moved_in_at = excluded.moved_in_at,
                moved_out_at = excluded.moved_out_at
            """,
            [
                .id(resident.id.rawValue), .text(resident.name), .text(profile.ageGroup),
                .text(profile.occupation), .text(profile.hobby), .text(profile.worry),
                .text(profile.personality), .date(resident.movedInAt),
                .date(resident.movedOutAt),
            ],
        )
        let id = SQLValue.id(resident.id.rawValue)
        try run("DELETE FROM resident_relationships WHERE resident_id = ?", [id])
        for (position, relationship) in resident.relationships.enumerated() {
            try run(
                """
                INSERT INTO resident_relationships
                    (resident_id, position, other_resident_id, description)
                VALUES (?, ?, ?, ?)
                """,
                [
                    id, .integer(Int64(position)), .id(relationship.resident.rawValue),
                    .text(relationship.description),
                ],
            )
        }
        try run("DELETE FROM resident_interests WHERE resident_id = ?", [id])
        for (position, interest) in resident.interests.enumerated() {
            try run(
                "INSERT INTO resident_interests (resident_id, position, interest_id) VALUES (?, ?, ?)",
                [id, .integer(Int64(position)), .id(interest.rawValue)],
            )
        }
    }

    /// Stores `post` and its topic tags.
    func insert(_ post: Post) throws(TownStoreError) {
        let author: SQLValue = switch post.author {
        case let .resident(resident):
            .id(resident.rawValue)

        case .you:
            .null
        }
        try run(
            """
            INSERT INTO posts (id, author_resident_id, text, happened_at, reply_target_id,
                origin, scene_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .id(post.id.rawValue), author, .text(post.text), .date(post.happenedAt),
                .id(post.replyTarget?.rawValue), post.origin.map { .text($0.code) } ?? .null,
                .id(post.sceneID?.rawValue),
            ],
        )
        for (position, tag) in post.topicTags.enumerated() {
            try run(
                "INSERT INTO post_topic_tags (post_id, position, tag) VALUES (?, ?, ?)",
                [.id(post.id.rawValue), .integer(Int64(position)), .text(tag)],
            )
        }
    }

    /// Stores `interest` new, or replaces the stored one with its id, sources included,
    /// keeping its excluded flag.
    func upsert(_ interest: Interest) throws(TownStoreError) {
        let id = SQLValue.id(interest.id.rawValue)
        try run(
            """
            INSERT INTO interests (id, term, first_mentioned_at, last_mentioned_at, mentions)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET term = excluded.term,
                first_mentioned_at = excluded.first_mentioned_at,
                last_mentioned_at = excluded.last_mentioned_at, mentions = excluded.mentions
            """,
            [
                id, .text(interest.term), .date(interest.firstMentionedAt),
                .date(interest.lastMentionedAt), .integer(Int64(interest.mentions)),
            ],
        )
        try run("DELETE FROM interest_source_posts WHERE interest_id = ?", [id])
        for (position, post) in interest.sourcePosts.enumerated() {
            try run(
                "INSERT INTO interest_source_posts (interest_id, position, post_id) VALUES (?, ?, ?)",
                [id, .integer(Int64(position)), .id(post.rawValue)],
            )
        }
    }

    func insert(_ event: TownEvent) throws(TownStoreError) {
        try run(
            """
            INSERT INTO events (id, kind, description, starts_at, ends_at, status,
                related_resident_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .id(event.id.rawValue), .text(event.kind.rawValue), .text(event.description),
                .date(event.startsAt), .date(event.endsAt), .text(event.status.code),
                .id(event.relatedResident?.rawValue),
            ],
        )
    }

    func insert(_ schedule: Schedule) throws(TownStoreError) {
        try run(
            "INSERT INTO schedule (id, next_ordinary_scene_due, last_ran_at) VALUES (1, ?, ?)",
            [.date(schedule.nextOrdinarySceneDue), .date(schedule.lastRanAt)],
        )
        try insert(schedule.pendingResponses)
    }

    func insert(_ pendingResponses: [Schedule.PendingResponse]) throws(TownStoreError) {
        for response in pendingResponses {
            try run(
                "INSERT INTO pending_responses (post_id, due_at) VALUES (?, ?)",
                [.id(response.post.rawValue), .date(response.dueAt)],
            )
        }
    }

    /// Stores a scene's posts and interests, removes the response it delivers, and moves
    /// the next ordinary scene's due time.
    func insert(_ scene: TownStore.SceneStep) throws(TownStoreError) {
        for post in scene.posts {
            try insert(post)
        }
        for interest in scene.interests {
            try upsert(interest)
        }
        for assignment in scene.residentInterests {
            try assign(assignment)
        }
        if let delivered = scene.deliveredResponse {
            try run(
                """
                DELETE FROM pending_responses WHERE rowid IN (
                    SELECT rowid FROM pending_responses WHERE post_id = ? AND due_at = ? LIMIT 1
                )
                """,
                [.id(delivered.post.rawValue), .date(delivered.dueAt)],
            )
        }
        if let due = scene.nextOrdinarySceneDue {
            try setNextOrdinarySceneDue(due)
        }
    }

    func setNextOrdinarySceneDue(_ due: Date) throws(TownStoreError) {
        try requireChange(run("UPDATE schedule SET next_ordinary_scene_due = ?", [.date(due)]))
    }

    /// Throws ``TownStoreError/notFound`` when a statement that names one row changed none.
    func requireChange(_ changed: Int) throws(TownStoreError) {
        guard changed > 0 else {
            throw .notFound
        }
    }
}

extension Post.Origin {
    /// The code a post's origin is stored as — part of the file format.
    var code: String {
        switch self {
        case .catchUp:
            "catch-up"

        case .event:
            "event"

        case .ordinary:
            "ordinary"

        case .response:
            "response"
        }
    }
}

extension TownEvent.Status {
    /// The code an event's status is stored as — part of the file format.
    var code: String {
        switch self {
        case .ended:
            "ended"

        case .ongoing:
            "ongoing"
        }
    }
}
