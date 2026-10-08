import Foundation

extension SQLiteConnection {
    func hasResponse(to id: Post.ID) throws(TownStoreError) -> Bool {
        try !rows(
            "SELECT id FROM posts WHERE reply_target_id = ? AND origin = 'response' LIMIT 1",
            [.id(id.rawValue)],
        ) { row throws(TownStoreError) in try row.uuid() }.isEmpty
    }

    /// Called before the new reply is inserted, so empty first replies also consume extraction.
    func extractedInterests(_ names: [String], source: Post) throws(TownStoreError) -> [Interest] {
        guard source.author == .you, try !hasResponse(to: source.id) else {
            return []
        }
        let existing = try includedInterests(includingExcluded: true)
        var interests: [Interest] = []
        for name in NameTerms.validated(names, in: source.text) {
            let previous = existing.first { NameTerms.key($0.term) == NameTerms.key(name) }
            guard previous?.sourcePosts.contains(source.id) != true else { continue }
            do throws(TownValueError) {
                try interests.append(Interest(
                    id: previous?.id ?? Interest.ID(),
                    term: previous?.term ?? name,
                    firstMentionedAt: min(
                        previous?.firstMentionedAt ?? source.happenedAt,
                        source.happenedAt,
                    ),
                    lastMentionedAt: max(
                        previous?.lastMentionedAt ?? source.happenedAt,
                        source.happenedAt,
                    ),
                    mentions: (previous?.mentions ?? 0) + 1,
                    sourcePosts: (previous?.sourcePosts ?? []) + [source.id],
                ))
            } catch { throw .rejectedRow(error) }
        }
        return interests
    }
}
