import Foundation
import SQLite3
import Testing

/// Why a ``RawDatabase`` call failed, with SQLite's code.
struct RawDatabaseError: Error, CustomStringConvertible {
    let code: Int32

    var description: String {
        "SQLite \(code)"
    }
}

/// A second connection to a store's file that a test reads and writes behind the store's
/// back: to look at the schema, to plant a row the store would never write, or to take a
/// snapshot of every table. It answers from SQLite directly, so it never agrees with the
/// store because it shares the store's code.
final class RawDatabase {
    private let handle: OpaquePointer

    /// Opens (or creates) the database at `url`.
    init(_ url: URL) throws {
        var opened: OpaquePointer?
        let status = sqlite3_open_v2(
            url.path(percentEncoded: false),
            &opened,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil,
        )
        guard status == SQLITE_OK, let opened else {
            sqlite3_close_v2(opened)
            throw RawDatabaseError(code: status)
        }
        handle = opened
    }

    /// Runs one or more statements that return nothing.
    func execute(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else {
            throw RawDatabaseError(code: status)
        }
    }

    /// Every row of `sql`, each column as text, `NULL` spelled "NULL".
    func rows(_ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard status == SQLITE_OK, let statement else {
            throw RawDatabaseError(code: status)
        }
        var rows: [[String]] = []
        while true {
            let step = sqlite3_step(statement)
            guard step == SQLITE_ROW else {
                guard step == SQLITE_DONE else {
                    throw RawDatabaseError(code: step)
                }
                return rows
            }
            rows.append((0 ..< sqlite3_column_count(statement)).map { column in
                guard let text = sqlite3_column_text(statement, column) else {
                    return "NULL"
                }
                return String(cString: text)
            })
        }
    }

    /// The first column of every row of `sql`.
    func strings(_ sql: String) throws -> [String] {
        try rows(sql).compactMap(\.first)
    }

    /// The first column of the first row of `sql`, as an integer.
    func integer(_ sql: String) throws -> Int {
        let text = try #require(strings(sql).first)
        return try #require(Int(text))
    }

    /// The schema version stored in the file.
    func userVersion() throws -> Int {
        try integer("PRAGMA user_version")
    }

    /// The names of the tables SQLite holds, sorted.
    func tableNames() throws -> [String] {
        try strings("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
    }

    /// Every row of every table, sorted, plus the schema version — what a failed step
    /// must leave exactly as it was.
    func snapshot() throws -> [String: [String]] {
        var snapshot = try ["user_version": [String(userVersion())]]
        for table in try tableNames() {
            snapshot[table] = try rows("SELECT * FROM \"\(table)\"")
                .map { $0.joined(separator: "|") }
                .sorted()
        }
        return snapshot
    }

    /// How many rows `table` holds.
    func count(_ table: String) throws -> Int {
        try integer("SELECT count(*) FROM \"\(table)\"")
    }

    deinit {
        sqlite3_close_v2(handle)
    }
}
