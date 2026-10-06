/// Why ``TownStore`` could not open, read, or write. A failed write has already been
/// rolled back whole when this is thrown, so the store is as it was before the step.
///
/// Payloads are SQLite result codes (extended codes, such as `787` for a foreign key),
/// Foundation error codes, versions, and counts — never SQL, a stored text, or a path,
/// which holds the user's home folder (`designing-errors` › No user data).
public enum TownStoreError: Error, Equatable, Sendable {
    /// Moving away closed the store but could not remove the `Town` directory; `code` is
    /// Foundation's file error code.
    case cannotDelete(code: Int32)
    /// The `Town` directory could not be created, or SQLite could not open or set up the
    /// file; `code` is SQLite's result code (`SQLITE_CANTOPEN`, 14, when the directory
    /// itself could not be made).
    case cannotOpen(code: Int32)
    /// The store was closed by ``TownStore/deleteEverything()``; nothing more can be read
    /// or written through it.
    case closed
    /// A date lies too far from 1970 to store as milliseconds.
    case dateOutOfRange
    /// A read was asked for fewer than one row.
    case invalidLimit(Int)
    /// A stored row could not be read back: a value missing, an id that is not a UUID, or
    /// a code this build does not know.
    case malformedRow
    /// Migrating to `version` failed with SQLite's `code`; nothing of the migration was
    /// kept, and the store did not open.
    case migrationFailed(version: Int, code: Int32)
    /// The file was written by a newer build: its schema is `found`, and this build reads
    /// up to `supported`. Opening changed nothing.
    case newerSchema(found: Int, supported: Int)
    /// The step names a row the store does not hold — an unknown post, interest, or
    /// event, or a schedule before founding.
    case notFound
    /// A stored row breaks a rule of the Core value it is read into.
    case rejectedRow(TownValueError)
    /// A statement failed with SQLite's `code`; the step it belonged to was rolled back.
    case statementFailed(code: Int32)
}
