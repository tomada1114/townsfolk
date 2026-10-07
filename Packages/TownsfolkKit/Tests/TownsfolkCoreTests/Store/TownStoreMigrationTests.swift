import Foundation
import Testing
import TownsfolkCore

/// Opening a store: creating schema v1, keeping a v1 file, and refusing what it cannot
/// open (`docs/architecture.md` › Persistence, › Quality targets: one migration test per
/// schema version).
@Suite("TownStore migrations")
struct TownStoreMigrationTests {
    /// Every table schema v1 holds, sorted — spelled out, since the schema is contract.
    static let version1Tables = [
        "events", "interest_source_posts", "interests", "pending_responses", "post_topic_tags",
        "posts", "resident_interests", "resident_relationships", "residents", "schedule",
        "town", "town_places",
    ]

    private static func expectVersion1(_ raw: RawDatabase) throws {
        #expect(try raw.userVersion() == 1)
        #expect(try raw.tableNames() == version1Tables)
        let indexes = try raw.strings(
            """
            SELECT name FROM sqlite_master
            WHERE type = 'index' AND name NOT LIKE 'sqlite_autoindex%' ORDER BY name
            """,
        )
        #expect(indexes == ["events_starts_at", "posts_happened_at"])
        #expect(try raw.strings("SELECT name FROM pragma_index_info('posts_happened_at')") == [
            "happened_at", "id",
        ])
        #expect(try raw.strings("SELECT name FROM pragma_index_info('events_starts_at')") == [
            "starts_at", "id",
        ])
    }

    // MARK: v0 → v1

    @Test
    func `a directory with no database gets town.sqlite at version 1`() async throws {
        try await withTownDirectory { directory in
            #expect(!FileManager.default.fileExists(atPath: directory.town.path()))
            _ = try TownStore(directory: directory.town)
            #expect(FileManager.default.fileExists(atPath: directory.database.path()))
            try Self.expectVersion1(directory.raw())
        }
    }

    @Test
    func `an empty version-0 file is migrated to version 1`() async throws {
        try await withTownDirectory { directory in
            try directory.makeTown()
            #expect(FileManager.default.createFile(
                atPath: directory.database.path(),
                contents: Data(),
            ))
            #expect(try directory.raw().userVersion() == 0)
            _ = try TownStore(directory: directory.town)
            try Self.expectVersion1(directory.raw())
        }
    }

    @Test
    func `a failed migration keeps nothing and names the version it was migrating to`(
    ) async throws {
        try await withTownDirectory { directory in
            try directory.makeTown()
            try directory.raw().execute("CREATE TABLE posts (unrelated TEXT)")
            #expect(throws: TownStoreError.migrationFailed(version: 1, code: 1)) {
                try TownStore(directory: directory.town)
            }
            let raw = try directory.raw()
            #expect(try raw.userVersion() == 0)
            #expect(try raw.tableNames() == ["posts"])
        }
    }

    // MARK: v1 → v1

    @Test
    func `reopening a version-1 file runs no migration and keeps every row`() async throws {
        try await withTownDirectory { directory in
            let founding = try StoreFixtures.founding()
            try await TownStore(directory: directory.town).found(founding)
            let before = try directory.raw().snapshot()

            let reopened = try TownStore(directory: directory.town)
            #expect(try directory.raw().snapshot() == before)
            #expect(try await reopened.town() == founding.town)
            #expect(try await reopened.schedule() == founding.schedule)
            let page = try await reopened.page(before: nil, limit: 10)
            #expect(page.entries.count == 3)
        }
    }

    // MARK: Refusing to open

    @Test
    func `a file from a newer build is refused with both versions and left byte for byte`(
    ) async throws {
        try await withTownDirectory { directory in
            try directory.makeTown()
            try directory.raw().execute("CREATE TABLE future (x TEXT); PRAGMA user_version = 2")
            let bytes = try Data(contentsOf: directory.database)

            #expect(throws: TownStoreError.newerSchema(found: 2, supported: 1)) {
                try TownStore(directory: directory.town)
            }
            #expect(try Data(contentsOf: directory.database) == bytes)
        }
    }

    @Test
    func `a directory that cannot be created is refused with SQLITE_CANTOPEN`() async throws {
        try await withTownDirectory { directory in
            let blocker = directory.root.appending(path: "blocker", directoryHint: .notDirectory)
            #expect(FileManager.default.createFile(
                atPath: blocker.path(),
                contents: Data("x".utf8),
            ))
            #expect(throws: TownStoreError.cannotOpen(code: 14)) {
                try TownStore(directory: blocker.appending(
                    path: "Town",
                    directoryHint: .isDirectory,
                ))
            }
        }
    }

    @Test
    func `a database path that is a directory is refused with SQLite's code`() async throws {
        try await withTownDirectory { directory in
            try FileManager.default.createDirectory(
                at: directory.database,
                withIntermediateDirectories: true,
            )
            #expect(throws: TownStoreError.cannotOpen(code: 14)) {
                try TownStore(directory: directory.town)
            }
        }
    }

    @Test
    func `a file that is not a database is refused with SQLITE_NOTADB`() async throws {
        try await withTownDirectory { directory in
            try directory.makeTown()
            let garbage = Data(String(repeating: "not a database ", count: 64).utf8)
            #expect(FileManager.default.createFile(
                atPath: directory.database.path(),
                contents: garbage,
            ))
            #expect(throws: TownStoreError.cannotOpen(code: 26)) {
                try TownStore(directory: directory.town)
            }
            #expect(try Data(contentsOf: directory.database) == garbage)
        }
    }
}
