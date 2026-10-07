import Foundation
import SQLite3

/// An open SQLite connection. Not `Sendable`: only ``TownStore`` holds one, inside its
/// isolation, and closes it in its `isolated deinit`.
struct SQLiteConnection {
    private let handle: OpaquePointer

    /// Opens or creates the database at `path` with extended result codes on.
    /// - Throws: ``TownStoreError/cannotOpen(code:)`` with SQLite's code.
    static func open(path: String) throws(TownStoreError) -> Self {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXRESCODE
        let status = sqlite3_open_v2(path, &opened, flags, nil)
        guard let pointer = opened else {
            throw .cannotOpen(code: status)
        }
        guard status == SQLITE_OK else {
            sqlite3_close_v2(pointer)
            throw .cannotOpen(code: status)
        }
        sqlite3_extended_result_codes(pointer, 1)
        return Self(handle: pointer)
    }

    /// Closes the connection; it must not be used afterwards.
    func close() {
        sqlite3_close_v2(handle)
    }

    /// Prepares `sql` and binds `values` to its parameters, in order.
    /// - Throws: ``TownStoreError/statementFailed(code:)``.
    func prepare(_ sql: SQL, _ values: [SQLValue]) throws(TownStoreError) -> SQLiteStatement {
        var prepared: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql.text, -1, &prepared, nil)
        guard status == SQLITE_OK, let prepared else {
            sqlite3_finalize(prepared)
            throw .statementFailed(code: status)
        }
        let statement = SQLiteStatement(pointer: prepared)
        try statement.bind(values)
        return statement
    }

    /// Runs `sql`, which returns no rows, with `values` bound.
    /// - Returns: How many rows it inserted, updated, or deleted.
    @discardableResult
    func run(_ sql: SQL, _ values: [SQLValue]) throws(TownStoreError) -> Int {
        let statement = try prepare(sql, values)
        _ = try statement.step()
        return Int(sqlite3_changes(handle))
    }

    /// Every row `sql` returns, each turned into a value by `read`.
    func rows<Row>(
        _ sql: SQL,
        _ values: [SQLValue],
        read: (inout SQLiteRow) throws(TownStoreError) -> Row,
    ) throws(TownStoreError) -> [Row] {
        let statement = try prepare(sql, values)
        var rows: [Row] = []
        while try statement.step() {
            var row = statement.row()
            try rows.append(read(&row))
        }
        return rows
    }

    /// The first row `sql` returns, or `nil` when it returns none.
    func firstRow<Row>(
        _ sql: SQL,
        _ values: [SQLValue],
        read: (inout SQLiteRow) throws(TownStoreError) -> Row,
    ) throws(TownStoreError) -> Row? {
        let statement = try prepare(sql, values)
        guard try statement.step() else {
            return nil
        }
        var row = statement.row()
        return try read(&row)
    }

    /// Runs `body` as one transaction: committed when it returns, rolled back whole when
    /// it or the commit throws — a deferred foreign-key failure surfaces at the commit.
    func transaction(_ body: () throws(TownStoreError) -> Void) throws(TownStoreError) {
        try run("BEGIN IMMEDIATE", [])
        do throws(TownStoreError) {
            try body()
            try run("COMMIT", [])
        } catch {
            rollBack()
            throw error
        }
    }

    /// Rolls back the open transaction, unless SQLite already did so itself, as it does
    /// after some errors (a full disk). The error that caused the rollback is the one
    /// reported: a rollback that cannot run leaves nothing more a caller could act on.
    private func rollBack() {
        guard sqlite3_get_autocommit(handle) == 0 else {
            return
        }
        sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
    }
}
