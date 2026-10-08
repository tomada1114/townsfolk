import Foundation

/// Reads used by the response rules. They keep the existing schema and exclude content
/// the writer has left out, even when it is still visible in the timeline.
extension TownStore {
    func responsePost(_ id: Post.ID) throws(TownStoreError) -> Post? {
        let connection = try liveConnection()
        let included = try connection.rows(
            "SELECT id FROM posts WHERE id = ? AND excluded = 0",
            [.id(id.rawValue)],
        ) { row throws(TownStoreError) in
            try row.uuid()
        }
        return included.isEmpty ? nil : try connection.post(id.rawValue, tuning: tuning)
    }

    /// Bounds the history before filtering, so an answered latest post never resurrects
    /// old schedules displaced by the cap. Atomic repair rechecks each candidate.
    func unscheduledYourPosts(maximum: Int) throws(TownStoreError) -> [Post] {
        guard maximum >= 1 else { throw .invalidLimit(maximum) }
        let connection = try liveConnection()
        let ids = try connection.rows(
            """
            SELECT id FROM posts WHERE author_resident_id IS NULL
            ORDER BY happened_at DESC, id DESC LIMIT ?
            """,
            [.integer(Int64(maximum))],
        ) { row throws(TownStoreError) in try row.uuid() }
        var candidates: [Post] = []
        for id in ids.reversed() {
            let postID = Post.ID(rawValue: id)
            guard try connection.responseRepairEligible(postID, maximum: maximum) else { continue }
            if let post = try connection.post(id, tuning: tuning) {
                candidates.append(post)
            }
        }
        return candidates
    }

    func hasResponse(to id: Post.ID) throws(TownStoreError) -> Bool {
        try !liveConnection().rows(
            "SELECT id FROM posts WHERE reply_target_id = ? AND origin = 'response' LIMIT 1",
            [.id(id.rawValue)],
        ) { row throws(TownStoreError) in try row.uuid() }.isEmpty
    }

    func lastScenePostTime() throws(TownStoreError) -> Date? {
        try liveConnection().rows(
            "SELECT happened_at FROM posts WHERE scene_id IS NOT NULL ORDER BY happened_at DESC LIMIT 1",
            [],
        ) { row throws(TownStoreError) in try row.date() }.first
    }

    func yourPostSeeds(before date: Date) throws(TownStoreError) -> [Post] {
        let connection = try liveConnection()
        let start = date.addingTimeInterval(-(tuning.yourPost.postSeedLifetime / .seconds(1)))
        let ids = try connection.rows(
            """
            SELECT id FROM posts WHERE author_resident_id IS NULL AND excluded = 0
            AND happened_at >= ? AND happened_at <= ?
            AND EXISTS (SELECT 1 FROM posts AS answer
            WHERE answer.reply_target_id = posts.id AND answer.origin = 'response')
            ORDER BY happened_at DESC, id DESC
            """,
            [.date(start), .date(date)],
        ) { row throws(TownStoreError) in try row.uuid() }
        var posts: [Post] = []
        for id in ids {
            if let post = try connection.post(id, tuning: tuning) {
                posts.append(post)
            }
        }
        return posts
    }
}
