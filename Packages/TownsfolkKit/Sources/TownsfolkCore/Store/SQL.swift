import Foundation

/// One value bound to a statement parameter.
enum SQLValue {
    case integer(Int64)
    case null
    case text(String)

    /// An id, stored as its uppercase UUID string.
    static func id(_ uuid: UUID) -> Self {
        .text(uuid.uuidString)
    }

    /// An optional id, stored as `NULL` when absent.
    static func id(_ uuid: UUID?) -> Self {
        uuid.map(id) ?? .null
    }

    /// A date, stored as whole milliseconds since 1970 UTC.
    static func date(_ date: Date) throws(TownStoreError) -> Self {
        try .integer(StoredTime.milliseconds(date))
    }

    /// An optional date, stored as `NULL` when absent.
    static func date(_ date: Date?) throws(TownStoreError) -> Self {
        guard let date else {
            return .null
        }
        return try .date(date)
    }
}

/// A statement's text, written only as a string literal. It conforms to
/// `ExpressibleByStringLiteral` and not to `ExpressibleByStringInterpolation`, so
/// `"… \(value) …"` does not compile: every value reaches SQLite through ``SQLValue``,
/// bound, and never as part of the statement.
struct SQL: ExpressibleByStringLiteral {
    let text: String

    /// The statement asking SQLite how it would run this one.
    var queryPlan: Self {
        Self(text: "EXPLAIN QUERY PLAN " + text)
    }

    init(stringLiteral text: String) {
        self.text = text
    }

    private init(text: String) {
        self.text = text
    }
}
