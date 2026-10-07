import Foundation

/// One row of the page query, before its post or event is read.
private struct PageKey {
    let isEvent: Bool
    let id: UUID
    let time: Int64
}

extension TownStore {
    /// Before any cursor: no stored time reaches `Int64.max`, and every id sorts above "".
    private static let newest = TimelineCursor(time: .max, id: "")

    /// The page query: one keyset range per table over its time index, merged newest
    /// first, so the cost of a page does not grow with the log and `OFFSET` is never used.
    private static let pageQuery: SQL = """
    SELECT 0 AS is_event, id, happened_at AS time FROM posts WHERE (happened_at, id) < (?1, ?2)
    UNION ALL
    SELECT 1, id, starts_at FROM events WHERE (starts_at, id) < (?1, ?2)
    ORDER BY time DESC, id DESC LIMIT ?3
    """

    /// Up to `limit` timeline entries — posts and events together — older than `cursor`,
    /// or the newest when `cursor` is `nil`, by time then id (requirements §3.8).
    /// - Throws: ``TownStoreError/invalidLimit(_:)`` for a limit below 1.
    public func page(
        before cursor: TimelineCursor?,
        limit: Int,
    ) throws(TownStoreError) -> TimelinePage {
        guard limit >= 1 else {
            throw .invalidLimit(limit)
        }
        let connection = try liveConnection()
        let start = cursor ?? Self.newest
        // One row past the page says whether an older entry remains.
        let fetch = limit == .max ? Int64.max : Int64(limit + 1)
        var keys = try connection.rows(
            Self.pageQuery,
            [.integer(start.time), .text(start.id), .integer(fetch)],
        ) { row throws(TownStoreError) in
            try PageKey(isEvent: row.flag(), id: row.uuid(), time: row.integer())
        }
        let hasOlder = keys.count > limit
        if hasOlder {
            keys.removeLast()
        }
        var entries: [TimelineEntry] = []
        for key in keys {
            try entries.append(entry(for: key, in: connection))
        }
        let older = keys.last.map { TimelineCursor(time: $0.time, id: $0.id.uuidString) }
        return TimelinePage(entries: entries, older: hasOlder ? older : nil)
    }

    /// The query plan SQLite chooses for the page query, one line per step — the seam
    /// the test asserting it stays on the time indexes reads.
    package func timelinePagePlan() throws(TownStoreError) -> [String] {
        let start = Self.newest
        return try liveConnection().rows(
            Self.pageQuery.queryPlan,
            [.integer(start.time), .text(start.id), .integer(1)],
        ) { row throws(TownStoreError) in
            _ = try row.integer()
            _ = try row.integer()
            _ = try row.integer()
            return try row.text()
        }
    }

    private func entry(
        for key: PageKey,
        in connection: SQLiteConnection,
    ) throws(TownStoreError) -> TimelineEntry {
        if key.isEvent {
            guard let event = try connection.event(key.id) else {
                throw .malformedRow
            }
            return .event(event)
        }
        guard let post = try connection.post(key.id, tuning: tuning) else {
            throw .malformedRow
        }
        return .post(post)
    }
}
