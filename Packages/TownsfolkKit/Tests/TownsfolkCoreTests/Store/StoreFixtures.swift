import Foundation
import Testing
import TownsfolkCore

/// A test's own `TownsfolkTests-<UUID>` directory, and the `Town` directory inside it the
/// store is handed. The `Town` directory does not exist until the store creates it.
struct TownDirectory {
    let root: URL

    var town: URL {
        root.appending(path: "Town", directoryHint: .isDirectory)
    }

    /// The database file, spelled out here rather than read from the store: its name is
    /// part of the file format.
    var database: URL {
        town.appending(path: "town.sqlite", directoryHint: .notDirectory)
    }

    func raw() throws -> RawDatabase {
        try RawDatabase(database)
    }

    /// Creates the `Town` directory, for a test that writes a file before the store opens.
    func makeTown() throws {
        try FileManager.default.createDirectory(at: town, withIntermediateDirectories: true)
    }
}

/// A resident to store; every field but the name has a value a test rarely cares about.
struct ResidentDraft {
    var name: String
    var id = Resident.ID()
    var movedInAt = StoreFixtures.morning
    var relationships: [Resident.Relationship] = []
    var interests: [Interest.ID] = []

    func make() throws -> Resident {
        try Resident(
            id: id,
            name: name,
            profile: StoreFixtures.profile(),
            movedInAt: movedInAt,
            relationships: relationships,
            interests: interests,
        )
    }
}

/// A resident's post in a scene of its own unless `scene` is given.
struct ResidentPostDraft {
    var author: Resident.ID
    var time = StoreFixtures.morning
    var text = "Bread is out at the bakery."
    var replyTarget: Post.ID?
    var topicTags: [String] = []
    var scene = SceneID()

    func make() throws -> Post {
        try Post(
            id: Post.ID(),
            author: .resident(author),
            text: text,
            happenedAt: time,
            replyTarget: replyTarget,
            topicTags: topicTags,
            origin: .ordinary,
            sceneID: scene,
        )
    }
}

/// A post of yours.
struct YourPostDraft {
    var time = StoreFixtures.morning
    var text = "Learning Rust today."
    var replyTarget: Post.ID?

    func make() throws -> Post {
        try Post(
            id: Post.ID(),
            author: .you,
            text: text,
            happenedAt: time,
            replyTarget: replyTarget,
        )
    }
}

/// An ongoing event lasting an hour.
struct EventDraft {
    private static let anHour: TimeInterval = 3_600

    var kind = EventKindID(rawValue: "rain")
    var time = StoreFixtures.morning
    var description = "It started raining."
    var relatedResident: Resident.ID?

    func make() throws -> TownEvent {
        try TownEvent(
            id: TownEvent.ID(),
            kind: kind,
            description: description,
            startsAt: time,
            endsAt: time.addingTimeInterval(Self.anHour),
            relatedResident: relatedResident,
        )
    }
}

/// A name you brought up once.
struct InterestDraft {
    var term: String
    var time = StoreFixtures.morning
    var sources: [Post.ID] = []

    func make() throws -> Interest {
        try Interest(
            id: Interest.ID(),
            term: term,
            firstMentionedAt: time,
            lastMentionedAt: time,
            mentions: 1,
            sourcePosts: sources,
        )
    }
}

/// Fixed times and a founded town a store test writes, so a stored date can be compared
/// to a literal.
enum StoreFixtures {
    /// 2026-10-01T09:00:00Z.
    static let morning = date("2026-10-01T09:00:00Z")
    /// 2026-10-01T09:06:00Z, when the founded town's next ordinary scene is due.
    static let firstDue = date("2026-10-01T09:06:00Z")

    private static let secondsPerMinute: TimeInterval = 60

    /// The moment `iso` names, an ISO 8601 date-time in UTC.
    static func date(_ iso: String) -> Date {
        do {
            return try Date(iso, strategy: .iso8601)
        } catch {
            preconditionFailure("not an ISO 8601 date: \(iso)")
        }
    }

    /// `count` minutes after ``morning``.
    static func minutes(_ count: Int) -> Date {
        morning.addingTimeInterval(TimeInterval(count) * secondsPerMinute)
    }

    static func profile() throws -> Resident.Profile {
        try Resident.Profile(
            ageGroup: "thirties",
            occupation: "baker",
            hobby: "fishing",
            worry: "the rent",
            personality: "cheerful",
        )
    }

    /// A founded town: three residents, one who knows another, the founding event, a
    /// schedule due at ``firstDue``, and a first scene of two posts, the second replying
    /// to the first.
    static func founding() throws -> TownStore.FoundingStep {
        let mio = Resident.ID()
        let ren = Resident.ID()
        let neighbors = try Resident.Relationship(resident: ren, description: "Neighbors.")
        let scene = SceneID()
        let first = try ResidentPostDraft(author: mio, topicTags: ["bakery"], scene: scene).make()
        let second = try ResidentPostDraft(
            author: ren,
            time: minutes(1),
            text: "Get there before eight.",
            replyTarget: first.id,
            scene: scene,
        ).make()
        return try TownStore.FoundingStep(
            town: Town(
                name: "Maplewood",
                setting: "A small town by a slow river.",
                places: ["the bakery", "the river", "the station"],
                foundedAt: morning,
            ),
            residents: [
                ResidentDraft(name: "Mio", id: mio, relationships: [neighbors]).make(),
                ResidentDraft(name: "Ren", id: ren).make(),
                ResidentDraft(name: "Aki").make(),
            ],
            foundingEvent: EventDraft(kind: .founding, description: "You moved to Maplewood.")
                .make(),
            schedule: Schedule(nextOrdinarySceneDue: firstDue, lastRanAt: morning),
            firstScene: TownStore.SceneStep(posts: [first, second]),
        )
    }
}

/// Runs `body` with a directory of its own, removed afterwards, so tests running in
/// parallel never share a file (`.claude/rules/testing.md` › Hygiene). `body` runs on the
/// caller's actor, so a `@MainActor` test can hand it a view model.
nonisolated(nonsending) func withTownDirectory(
    _ body: (TownDirectory) async throws -> Void,
) async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "TownsfolkTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(TownDirectory(root: root))
}

/// Runs `body` with a store opened on a fresh directory.
nonisolated(nonsending) func withStore(
    _ body: (TownStore, TownDirectory) async throws -> Void,
) async throws {
    try await withTownDirectory { directory in
        let store = try TownStore(directory: directory.town)
        try await body(store, directory)
    }
}

/// Runs `body` with a store holding ``StoreFixtures/founding()``.
nonisolated(nonsending) func withFoundedStore(
    _ body: (TownStore, TownStore.FoundingStep, TownDirectory) async throws -> Void,
) async throws {
    try await withStore { store, directory in
        let founding = try StoreFixtures.founding()
        try await store.found(founding)
        try await body(store, founding, directory)
    }
}

/// The first change `changes` delivers.
func firstChange(_ changes: AsyncStream<TownStoreChange>) async -> TownStoreChange? {
    var iterator = changes.makeAsyncIterator()
    return await iterator.next()
}
