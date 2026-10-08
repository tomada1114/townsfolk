import Foundation

/// Posting and legacy repair keep response caps inside the same store transaction.
extension TownStore {
    func storeScheduledYourPost(
        _ post: Post,
        responses: [Schedule.PendingResponse],
        maximum: Int,
    ) throws(TownStoreError) {
        guard !Task.isCancelled else { throw .cancelled }
        guard maximum >= 1 else { throw .invalidLimit(maximum) }
        guard post.author == .you else { throw .rejectedRow(.notAllowed(.origin)) }
        try commit(.yourPostStored(post.id)) { connection throws(TownStoreError) in
            guard try connection.schedule() != nil else { throw .notFound }
            try connection.insert(post)
            try connection.insert(responses)
            try connection.pruneResponses(maximum: maximum)
        }
    }

    /// A read made by the engine may already be stale by this actor hop. Eligibility,
    /// insertion and pruning are therefore decided together here, without suspension.
    func repairResponses(
        to post: Post.ID,
        adding responses: [Schedule.PendingResponse],
        maximum: Int,
    ) throws(TownStoreError) -> Bool {
        guard !Task.isCancelled else { throw .cancelled }
        guard maximum >= 1 else { throw .invalidLimit(maximum) }
        let connection = try liveConnection()
        var repaired = false
        try connection.transaction { () throws(TownStoreError) in
            guard try connection.responseRepairEligible(post, maximum: maximum) else {
                return
            }
            guard try connection.schedule() != nil else { throw .notFound }
            try connection.insert(responses)
            try connection.pruneResponses(maximum: maximum)
            repaired = true
        }
        if repaired {
            announce(.pendingResponsesChanged)
        }
        return repaired
    }
}

extension SQLiteConnection {
    /// Cap membership is determined before exclusions or previously delivered scenes.
    func responseRepairEligible(_ post: Post.ID, maximum: Int) throws(TownStoreError) -> Bool {
        try !rows(
            """
            SELECT id FROM posts WHERE id = ? AND excluded = 0
            AND author_resident_id IS NULL
            AND id IN (SELECT id FROM posts WHERE author_resident_id IS NULL
            ORDER BY happened_at DESC, id DESC LIMIT ?)
            AND NOT EXISTS (SELECT 1 FROM pending_responses WHERE post_id = posts.id)
            AND NOT EXISTS (SELECT 1 FROM posts AS answer
            WHERE answer.reply_target_id = posts.id AND answer.origin = 'response')
            """,
            [.id(post.rawValue), .integer(Int64(maximum))],
        ) { row throws(TownStoreError) in try row.uuid() }.isEmpty
    }

    /// The newest pending post groups survive regardless of submission actor ordering.
    func pruneResponses(maximum: Int) throws(TownStoreError) {
        try run(
            """
            DELETE FROM pending_responses WHERE post_id NOT IN (
                SELECT posts.id FROM posts JOIN pending_responses ON post_id = posts.id
                GROUP BY posts.id ORDER BY happened_at DESC, posts.id DESC LIMIT ?
            )
            """,
            [.integer(Int64(maximum))],
        )
    }
}
