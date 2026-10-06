import Foundation
import SQLite3

/// Reads the current row's columns one after another, in the order the `SELECT` lists
/// them, so no call site counts column indexes by hand.
struct SQLiteRow {
    private let pointer: OpaquePointer
    private var column: Int32 = 0

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The next column as an integer, or `nil` when it is `NULL`.
    mutating func optionalInteger() -> Int64? {
        defer { column += 1 }
        guard sqlite3_column_type(pointer, column) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(pointer, column)
    }

    /// The next column as text, or `nil` when it is `NULL`.
    /// - Throws: ``TownStoreError/malformedRow`` when it is not UTF-8.
    mutating func optionalText() throws(TownStoreError) -> String? {
        defer { column += 1 }
        guard let bytes = sqlite3_column_text(pointer, column) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(pointer, column))
        guard let text = String(
            bytes: UnsafeBufferPointer(start: bytes, count: count),
            encoding: .utf8,
        )
        else {
            throw .malformedRow
        }
        return text
    }

    /// The next column as an integer.
    /// - Throws: ``TownStoreError/malformedRow`` when it is `NULL`.
    mutating func integer() throws(TownStoreError) -> Int64 {
        guard let value = optionalInteger() else {
            throw .malformedRow
        }
        return value
    }

    /// The next column as text.
    /// - Throws: ``TownStoreError/malformedRow`` when it is `NULL` or not UTF-8.
    mutating func text() throws(TownStoreError) -> String {
        guard let value = try optionalText() else {
            throw .malformedRow
        }
        return value
    }

    /// The next column as an `Int`.
    mutating func count() throws(TownStoreError) -> Int {
        try Int(integer())
    }

    /// The next column as a flag stored as `0` or `1`.
    mutating func flag() throws(TownStoreError) -> Bool {
        try integer() != 0
    }

    /// The next column as a date stored in milliseconds.
    mutating func date() throws(TownStoreError) -> Date {
        try StoredTime.date(integer())
    }

    /// The next column as an optional date.
    mutating func optionalDate() -> Date? {
        optionalInteger().map(StoredTime.date)
    }

    /// The next column as a UUID.
    /// - Throws: ``TownStoreError/malformedRow`` when it is `NULL` or not a UUID.
    mutating func uuid() throws(TownStoreError) -> UUID {
        guard let uuid = try UUID(uuidString: text()) else {
            throw .malformedRow
        }
        return uuid
    }

    /// The next column as an optional UUID.
    /// - Throws: ``TownStoreError/malformedRow`` when it is set but not a UUID.
    mutating func optionalUUID() throws(TownStoreError) -> UUID? {
        guard let text = try optionalText() else {
            return nil
        }
        guard let uuid = UUID(uuidString: text) else {
            throw .malformedRow
        }
        return uuid
    }
}

/// One prepared statement, finalized when the last reference goes.
final class SQLiteStatement {
    /// SQLite's `SQLITE_TRANSIENT`, a macro Swift does not import: SQLite copies a bound
    /// text before the call returns, so the Swift string may go away.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// Binds `values` to parameters 1, 2, … in order.
    func bind(_ values: [SQLValue]) throws(TownStoreError) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status = switch value {
            case let .integer(number):
                sqlite3_bind_int64(pointer, index, number)

            case .null:
                sqlite3_bind_null(pointer, index)

            case let .text(text):
                sqlite3_bind_text(pointer, index, text, Int32(text.utf8.count), Self.transient)
            }
            guard status == SQLITE_OK else {
                throw .statementFailed(code: status)
            }
        }
    }

    /// Steps once: `true` with a row to read, `false` when the statement is done.
    func step() throws(TownStoreError) -> Bool {
        let status = sqlite3_step(pointer)
        switch status {
        case SQLITE_ROW:
            return true

        case SQLITE_DONE:
            return false

        default:
            throw .statementFailed(code: status)
        }
    }

    /// A reader over the current row's columns, from the first.
    func row() -> SQLiteRow {
        SQLiteRow(pointer: pointer)
    }

    deinit {
        sqlite3_finalize(pointer)
    }
}
