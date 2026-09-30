# ADR-0004: The town in one SQLite file owned by Core, and settings in UserDefaults

- **Status:** Accepted 2026-09-30
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

Townsfolk keeps its whole history on the Mac (requirements §3.8, §5): every post, event,
and move for the town's life — about 1,000 posts a day at Fast, and a timeline that stays
responsive past 100,000 posts, loaded newest first as you scroll — plus the town, its
residents, the names you brought up, and the schedule. The log is the source of truth
every model call is rebuilt from. Moving to another town deletes all of it for good
(§3.9); quitting mid-founding keeps nothing (§3.1). The stored format is versioned, and
every change ships a migration (§5). Settings — display name, language, speed, and
whether the town keeps moving in other apps — outlive a town, because founding the next
one reuses the language and the name.

The template ships no persistence. `docs/architecture.md` › What is contract and what is
private makes `UserDefaults` keys and file formats contract, and puts a format's version
and migration in Core, tested against a sample of the previous format.

## Decision drivers

- Crash safety: a scene's posts, the schedule, and the names it touched change together
  or not at all, or a crash repeats or loses a scene.
- Paging 100,000+ posts newest first without loading them.
- Migrations under the coverage floor and in CI.
- Zero dependencies (README › Why zero dependencies?).
- Swift 6: what crosses an actor is `Sendable`.

## Considered options

1. **SQLite through the system `SQLite3` library, owned by Core.**
2. **SwiftData.** It runs under `swift test`, but its models are classes bound to a
   model context, so Core's `Sendable` value types would be mapped to and from them
   anyway, and the stored schema and its migrations are SwiftData's to lay out rather
   than the app's.
3. **JSON files** — one append-only file per day and small state files. The simplest to
   read, but a write that spans files is not atomic, and paging, lookups, and migrations
   are hand-written over files.
4. **GRDB.swift**, a mature SQLite toolkit. It passes the dependency checklist's
   license, continuity, platform, and build-time items, but not Need: the system library
   covers a handful of tables, and it would be the repository's first dependency.

## Decision

**The town lives in one SQLite database**, `town.sqlite`, in a `Town` directory under the
app container's Application Support directory. `TownsfolkCore` owns it through
`import SQLite3` — the SDK's system library module, which links with no extra settings
and is not on Core's banned imports. A `TownStore` actor holds the connection; every
read and write goes through it and takes and returns Core value types. The composition
root hands `TownStore` its directory, so a test uses a temporary directory or an
in-memory database. There is no port: the store runs the same under `swift test` as in
the app, so it is tested directly.

- **Tables** follow requirements §5 — the town, residents, posts, events (moves
  included), the names you brought up with their source posts, and the schedule with its
  pending responses — with an index on the posts' `happened_at` for newest-first paging.
- **One transaction per step of the town:** a scene's posts, topic tags, touched names,
  and next due time; a new resident with its move event; a founded town, written only
  after all of its generation succeeded, so quitting mid-founding leaves nothing.
- **Versions.** `PRAGMA user_version` holds the schema version. Core keeps an ordered
  list of migration steps, and opening the store runs the pending ones in one
  transaction. Each step has a test that builds the previous version's database and
  checks what the step leaves.
- **Moving away** closes the store and deletes the `Town` directory — the database and
  its companion files — before the next town is founded into a new one.
- **Settings are `UserDefaults` keys**, outside the `Town` directory so moving away keeps
  them: `settings.displayName` (String), `settings.language` (`"en"` or `"ja"`),
  `settings.speed` (`"slow"`, `"normal"`, or `"fast"`), and
  `settings.keepsMovingInOtherApps` (Bool). Core reads and writes them through an
  injected `UserDefaults`, so a test passes its own suite. ADR-0007 adds `AppleLanguages`,
  the one key macOS reads.

SQLite beat SwiftData because the domain stays in value types with no mapping layer,
and the schema and its migrations are the app's own, readable and tested in Core; it
beat JSON files on atomicity and paging; it beat GRDB on the Need item, at the cost of
the binding code GRDB would have written.

## Consequences

### Positive

- A crash is harmless: the town resumes from the last complete step.
- Paging, a lookup by id (a reply's quote), and the recent window a scene is built from
  are indexed queries.
- The store and its migrations are under the coverage floor and run in CI.
- SQLite reads files written by any SQLite 3 version, so an OS update to the library
  strands no town.

### Negative

- SQL and the C API's binding are hand-written: a few hundred lines plus their tests.
  Under Swift 6 the actor closes its connection in an `isolated deinit`; a plain
  `deinit` does not compile, because the handle is not `Sendable`.
- The table layout and the four settings keys are contract (`docs/architecture.md`):
  renaming one means a migration.
- Residents' long-term memory (Later) will read this file; if it needs text search over
  the log, SQLite's full-text search is the first thing to check.

### Follow-ups

- `TownStore` with its first schema version and migration harness, and the settings
  keys — issues in the backlog.
- `docs/architecture.md` › What is contract and what is private names this database and
  these keys (done with this ADR).

## Open questions

None.

## Sources

- Experiment on this repository's toolchain (Swift 6.3.2, Xcode 26.5, macOS 27.0),
  2026-09-30: a SwiftPM target with `import SQLite3` and no linker settings passed
  `swift test` in Swift 6 mode with warnings as errors, for a file and for `:memory:`;
  newest-first `LIMIT` over an indexed timestamp and `PRAGMA user_version` worked;
  `sqlite3_libversion()` returned 3.54.0. A plain `deinit` closing the handle failed with
  "cannot access property 'db' with a non-Sendable type 'OpaquePointer?' from
  nonisolated deinit"; `isolated deinit` passed.
- Experiment, same date and toolchain: a SwiftData `@Model` in a `VersionedSchema`, an
  in-memory `ModelContainer`, and a `@ModelActor` passed `swift test` with no
  diagnostics.
- <https://www.sqlite.org/formatchng.html> — "Newer versions of SQLite can always read
  and/or write database files created by older versions of SQLite, back to version 3.0.0
  (2004-06-18)." — checked 2026-09-30
- <https://developer.apple.com/documentation/swiftdata/versionedschema> and
  <https://developer.apple.com/documentation/swiftdata/schemamigrationplan> — macOS
  14.0+ — checked 2026-09-30
- <https://github.com/groue/GRDB.swift> — v7.11.1, released 2026-06-18; MIT; not
  archived; `platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v7)]`; no
  binary target or build plugin — checked 2026-09-30

## Related

- [ADR-0002](0002-sandbox-posture.md) — the container the file lives in.
- [ADR-0005](0005-foundation-models-in-core.md) — every model call is built from this
  log.
- [ADR-0007](0007-english-and-japanese.md) — the language setting and `AppleLanguages`.
