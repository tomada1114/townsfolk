import Foundation
import SQLite3

/// The town's log: every post, event, resident, name you brought up, and the schedule,
/// kept in one SQLite database, `town.sqlite`, in the `Town` directory the composition
/// root hands it (`docs/architecture.md` › Persistence). Every model call is rebuilt from
/// it, and the timeline pages through it.
///
/// Each step of the town is one transaction that commits whole or not at all, so a crash
/// neither loses nor repeats a scene; each committed step is announced on ``changes()``.
/// Every read and write takes and returns Core values, and every value reaches SQLite
/// bound, never spliced into a statement. Time is always passed in: the store never
/// reads the clock, and it keeps every date to the millisecond.
///
/// There is no port in front of it — it runs the same under `swift test`, against a
/// temporary directory.
public actor TownStore {
    /// The database's name inside the `Town` directory — part of the file format.
    private static let fileName = "town.sqlite"

    /// What reads check stored values against, and the recent window's length.
    let tuning: Tuning
    private let directory: URL
    /// The open connection; `nil` once ``deleteEverything()`` closed it.
    private var connection: SQLiteConnection?
    private var subscribers: [AsyncStream<TownStoreChange>.Continuation] = []

    /// Opens the town in `directory`, creating the directory and the database as needed
    /// and migrating an older schema to the newest, in one transaction.
    ///
    /// - Parameters:
    ///   - directory: The `Town` directory — Application Support/Town/ in the app, a
    ///     temporary directory in a test. Moving away deletes it whole.
    ///   - tuning: The limits stored values are read back against, and the recent window.
    /// - Throws: ``TownStoreError/cannotOpen(code:)`` when the directory or the file cannot
    ///   be opened, ``TownStoreError/newerSchema(found:supported:)`` for a file from a
    ///   newer build (left unchanged), or ``TownStoreError/migrationFailed(version:code:)``.
    public init(directory: URL, tuning: Tuning = .default) throws(TownStoreError) {
        self.directory = directory
        self.tuning = tuning
        connection = try Self.openDatabase(in: directory)
    }

    private static func openDatabase(in directory: URL) throws(TownStoreError) -> SQLiteConnection {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
        } catch {
            throw .cannotOpen(code: SQLITE_CANTOPEN)
        }
        let file = directory.appending(path: fileName, directoryHint: .notDirectory)
        let opened = try SQLiteConnection.open(path: file.path(percentEncoded: false))
        do throws(TownStoreError) {
            try configure(opened)
            try migrate(opened)
        } catch {
            opened.close()
            throw error
        }
        return opened
    }

    /// Turns foreign keys on: SQLite keeps them off unless each connection asks.
    private static func configure(_ opened: SQLiteConnection) throws(TownStoreError) {
        do throws(TownStoreError) {
            try opened.run("PRAGMA foreign_keys = ON", [])
        } catch {
            throw .cannotOpen(code: code(of: error))
        }
    }

    /// Brings the schema to ``TownSchema/latestVersion``, running each migration newer than
    /// the file's `user_version` in order, all in one transaction.
    private static func migrate(_ opened: SQLiteConnection) throws(TownStoreError) {
        let found = try userVersion(of: opened)
        let latest = TownSchema.latestVersion
        guard found <= latest else {
            throw .newerSchema(found: found, supported: latest)
        }
        let pending = TownSchema.migrations.filter { $0.version > found }
        guard !pending.isEmpty else {
            return
        }
        var migrating = found
        do throws(TownStoreError) {
            try opened.transaction { () throws(TownStoreError) in
                for migration in pending {
                    migrating = migration.version
                    for statement in migration.statements {
                        try opened.run(statement, [])
                    }
                }
            }
        } catch {
            throw .migrationFailed(version: migrating, code: code(of: error))
        }
    }

    /// The file's `user_version`; reading it is also what fails for a file that is not a
    /// database.
    private static func userVersion(of opened: SQLiteConnection) throws(TownStoreError) -> Int {
        do throws(TownStoreError) {
            let version = try opened
                .firstRow("PRAGMA user_version", []) { row throws(TownStoreError) in
                    try row.count()
                }
            return version ?? 0
        } catch {
            throw .cannotOpen(code: code(of: error))
        }
    }

    /// The SQLite code inside an error raised while opening.
    private static func code(of error: TownStoreError) -> Int32 {
        if case let .statementFailed(code) = error {
            return code
        }
        return SQLITE_ERROR
    }

    /// A stream of every step committed from now on, for one subscriber; each call
    /// returns a stream of its own, so every subscriber receives every change. Each step
    /// announces one change naming the step, not one per effect (``TownStoreChange``), so
    /// a subscriber re-reads what it shows on any change. It finishes when everything is
    /// deleted, or at once if that already happened.
    public func changes() -> AsyncStream<TownStoreChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: TownStoreChange.self)
        if connection == nil {
            continuation.finish()
        } else {
            subscribers.append(continuation)
        }
        return stream
    }

    /// Moving away: closes the connection and removes the `Town` directory — the database
    /// and its companion files (requirements §3.9). Every later call throws
    /// ``TownStoreError/closed``, and every change stream finishes.
    /// - Throws: ``TownStoreError/closed`` if already deleted, or
    ///   ``TownStoreError/cannotDelete(code:)`` when the directory could not be removed —
    ///   the store is closed either way.
    public func deleteEverything() throws(TownStoreError) {
        let live = try liveConnection()
        live.close()
        connection = nil
        defer {
            for subscriber in subscribers {
                subscriber.finish()
            }
            subscribers = []
        }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch CocoaError.fileNoSuchFile {
            // Already gone, which is what moving away asks for.
        } catch {
            throw .cannotDelete(code: Int32(truncatingIfNeeded: (error as NSError).code))
        }
        announce(.everythingDeleted)
    }

    /// The open connection.
    /// - Throws: ``TownStoreError/closed`` after ``deleteEverything()``.
    func liveConnection() throws(TownStoreError) -> SQLiteConnection {
        guard let connection else {
            throw .closed
        }
        return connection
    }

    /// Hands `change` to every subscriber still listening, forgetting the rest.
    func announce(_ change: TownStoreChange) {
        subscribers.removeAll { subscriber in
            if case .terminated = subscriber.yield(change) {
                return true
            }
            return false
        }
    }

    isolated deinit {
        connection?.close()
        for subscriber in subscribers {
            subscriber.finish()
        }
    }
}
