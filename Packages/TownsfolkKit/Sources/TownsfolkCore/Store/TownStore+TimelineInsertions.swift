import Foundation

/// A run-local insertion boundary, never persisted: posts and events retain their rowids
/// because neither table deletes rows until the entire store is closed and removed.
package struct TimelineInsertionCursor: Sendable {
    var post: Int64 = 0
    var event: Int64 = 0
}

package struct TimelineInsertions: Sendable {
    package var entries: [TimelineEntry] = []
    var cursor = TimelineInsertionCursor()
}

/// Cursor capture and subscription belong to one actor turn. A failed capture retains
/// the stream and requests a full non-live recovery before replaying from zero.
package struct TimelineObservation: Sendable {
    package let changes: AsyncStream<TownStoreChange>
    package let cursor: TimelineInsertionCursor
    package let failedBoundary: Bool
}

extension TownStore {
    private static func insertionCursor(
        in connection: SQLiteConnection,
    ) throws(TownStoreError) -> TimelineInsertionCursor {
        try connection.firstRow(
            "SELECT (SELECT COALESCE(MAX(rowid), 0) FROM posts), (SELECT COALESCE(MAX(rowid), 0) FROM events)",
            [],
        ) { row throws(TownStoreError) in
            try TimelineInsertionCursor(post: row.integer(), event: row.integer())
        } ?? TimelineInsertionCursor()
    }

    /// Captured before the first page read, so insertions committed during that read
    /// remain discoverable even when their town timestamps precede loaded rows.
    private func timelineInsertionCursor() throws(TownStoreError) -> TimelineInsertionCursor {
        let connection = try liveConnection()
        var cursor = TimelineInsertionCursor()
        try connection.transaction { () throws(TownStoreError) in
            cursor = try Self.insertionCursor(in: connection)
        }
        return cursor
    }

    /// No suspension separates the boundary from registration, so every later commit
    /// is both announced and above the boundary, regardless of its stored timestamp.
    package func timelineObservation() -> TimelineObservation {
        var cursor = TimelineInsertionCursor()
        var failed = false
        do {
            cursor = try timelineInsertionCursor()
        } catch {
            failed = true
        }
        return TimelineObservation(changes: changes(), cursor: cursor, failedBoundary: failed)
    }

    /// Reads both tables and their next boundary in one transaction. A decoding failure
    /// returns no cursor, so the caller retries the same committed range.
    package func timelineInsertions(
        after cursor: TimelineInsertionCursor,
    ) throws(TownStoreError) -> TimelineInsertions {
        let connection = try liveConnection()
        var result = TimelineInsertions()
        try connection.transaction { () throws(TownStoreError) in
            let next = try Self.insertionCursor(in: connection)
            let keys = try connection.rows(
                """
                SELECT 0, id FROM posts WHERE rowid > ?1 AND rowid <= ?2
                UNION ALL
                SELECT 1, id FROM events WHERE rowid > ?3 AND rowid <= ?4
                """,
                [
                    .integer(cursor.post),
                    .integer(next.post),
                    .integer(cursor.event),
                    .integer(next.event),
                ],
            ) { row throws(TownStoreError) in
                try (row.flag(), row.uuid())
            }
            for (isEvent, id) in keys {
                if isEvent {
                    guard let event = try connection.event(id) else { throw .malformedRow }
                    result.entries.append(.event(event))
                } else {
                    guard let post = try connection.post(id, tuning: tuning)
                    else { throw .malformedRow }
                    result.entries.append(.post(post))
                }
            }
            result.cursor = next
        }
        return result
    }
}
