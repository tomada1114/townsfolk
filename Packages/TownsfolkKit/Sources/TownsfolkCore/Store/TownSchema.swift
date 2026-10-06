/// The town database's schema, as the ordered list of migrations that builds it. The
/// schema is part of the file format, so it is contract (`docs/architecture.md` › What is
/// contract and what is private): a shipped migration is never edited, and a change is a
/// new one appended here, with a test that builds the previous version's file.
///
/// Conventions every table follows:
/// - an id is a UUID's uppercase string (`UUID.uuidString`);
/// - a date is whole milliseconds since 1970 UTC (``StoredTime``);
/// - a flag is `0` or `1`;
/// - a list inside a value (a post's tags, a town's places) is a child table ordered by
///   `position`, from 0;
/// - every foreign key is deferred to the commit, so one step may write rows that point at
///   each other in any order;
/// - an enum is stored as a short lowercase code and decoded by the store, with no `CHECK`
///   on it, so a later version can add a code without rebuilding the table.
enum TownSchema {
    /// One step from the version before `version` to `version`. Its statements run in the
    /// one transaction that opening the store migrates in, and its last statement sets
    /// `PRAGMA user_version` to `version` — a pragma takes no bound value, so each
    /// migration spells its own.
    struct Migration {
        let version: Int
        let statements: [SQL]
    }

    /// Every migration, oldest first; the last one's version is the newest schema.
    static let migrations = [version1]

    /// The newest schema version this build reads and writes.
    static var latestVersion: Int {
        migrations.last?.version ?? 0
    }

    /// Schema v1: requirements §5, plus a post's scene id and the "excluded from later
    /// contexts" flag on posts and interests (§3.11).
    private static let version1 = Migration(
        version: 1,
        statements: [
            """
            CREATE TABLE town (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                name TEXT NOT NULL,
                setting TEXT NOT NULL,
                founded_at INTEGER NOT NULL
            ) STRICT
            """,
            """
            CREATE TABLE town_places (
                position INTEGER PRIMARY KEY,
                name TEXT NOT NULL
            ) STRICT
            """,
            """
            CREATE TABLE residents (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                age_group TEXT NOT NULL,
                occupation TEXT NOT NULL,
                hobby TEXT NOT NULL,
                worry TEXT NOT NULL,
                personality TEXT NOT NULL,
                moved_in_at INTEGER NOT NULL,
                moved_out_at INTEGER
            ) STRICT
            """,
            """
            CREATE TABLE resident_relationships (
                resident_id TEXT NOT NULL
                    REFERENCES residents (id) DEFERRABLE INITIALLY DEFERRED,
                position INTEGER NOT NULL,
                other_resident_id TEXT NOT NULL
                    REFERENCES residents (id) DEFERRABLE INITIALLY DEFERRED,
                description TEXT NOT NULL,
                PRIMARY KEY (resident_id, position)
            ) STRICT, WITHOUT ROWID
            """,
            """
            CREATE TABLE interests (
                id TEXT PRIMARY KEY NOT NULL,
                term TEXT NOT NULL,
                first_mentioned_at INTEGER NOT NULL,
                last_mentioned_at INTEGER NOT NULL,
                mentions INTEGER NOT NULL,
                excluded INTEGER NOT NULL DEFAULT 0 CHECK (excluded IN (0, 1))
            ) STRICT
            """,
            """
            CREATE TABLE resident_interests (
                resident_id TEXT NOT NULL
                    REFERENCES residents (id) DEFERRABLE INITIALLY DEFERRED,
                position INTEGER NOT NULL,
                interest_id TEXT NOT NULL
                    REFERENCES interests (id) DEFERRABLE INITIALLY DEFERRED,
                PRIMARY KEY (resident_id, position)
            ) STRICT, WITHOUT ROWID
            """,
            """
            CREATE TABLE posts (
                id TEXT PRIMARY KEY NOT NULL,
                author_resident_id TEXT
                    REFERENCES residents (id) DEFERRABLE INITIALLY DEFERRED,
                text TEXT NOT NULL,
                happened_at INTEGER NOT NULL,
                reply_target_id TEXT
                    REFERENCES posts (id) DEFERRABLE INITIALLY DEFERRED,
                origin TEXT,
                scene_id TEXT,
                excluded INTEGER NOT NULL DEFAULT 0 CHECK (excluded IN (0, 1))
            ) STRICT
            """,
            "CREATE INDEX posts_happened_at ON posts (happened_at, id)",
            """
            CREATE TABLE post_topic_tags (
                post_id TEXT NOT NULL
                    REFERENCES posts (id) DEFERRABLE INITIALLY DEFERRED,
                position INTEGER NOT NULL,
                tag TEXT NOT NULL,
                PRIMARY KEY (post_id, position)
            ) STRICT, WITHOUT ROWID
            """,
            """
            CREATE TABLE interest_source_posts (
                interest_id TEXT NOT NULL
                    REFERENCES interests (id) DEFERRABLE INITIALLY DEFERRED,
                position INTEGER NOT NULL,
                post_id TEXT NOT NULL
                    REFERENCES posts (id) DEFERRABLE INITIALLY DEFERRED,
                PRIMARY KEY (interest_id, position)
            ) STRICT, WITHOUT ROWID
            """,
            """
            CREATE TABLE events (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                description TEXT NOT NULL,
                starts_at INTEGER NOT NULL,
                ends_at INTEGER NOT NULL,
                status TEXT NOT NULL,
                related_resident_id TEXT
                    REFERENCES residents (id) DEFERRABLE INITIALLY DEFERRED
            ) STRICT
            """,
            "CREATE INDEX events_starts_at ON events (starts_at, id)",
            """
            CREATE TABLE schedule (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                next_ordinary_scene_due INTEGER NOT NULL,
                last_ran_at INTEGER NOT NULL
            ) STRICT
            """,
            """
            CREATE TABLE pending_responses (
                post_id TEXT NOT NULL
                    REFERENCES posts (id) DEFERRABLE INITIALLY DEFERRED,
                due_at INTEGER NOT NULL
            ) STRICT
            """,
            "PRAGMA user_version = 1",
        ],
    )
}
