import Foundation
import FoundationModels
import os
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// A generator that answers the same value every time: all zeros reach the bottom of every
/// range, all ones the top, so a test can check that a range's ends are included.
struct RepeatingGenerator: RandomNumberGenerator, Sendable {
    let value: UInt64

    func next() -> UInt64 {
        value
    }
}

/// The thermal state a test hands the engine, changeable mid-test.
final class ThermalReading: Sendable {
    private let state: OSAllocatedUnfairLock<ThermalState>

    var current: ThermalState {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    init(_ initial: ThermalState) {
        state = OSAllocatedUnfairLock(initialState: initial)
    }
}

/// The residents engine suites found towns with. Each has a profile of their own and moves
/// in a minute after the one before, so the roster's order — the store's moved-in order —
/// never depends on a random id.
enum EngineCast {
    /// The minute after nine each resident moved in.
    private enum MovedIn {
        static let mika = 0
        static let jun = 1
        static let aki = 2
        static let ren = 3
        static let sora = 4
    }

    static func mika() throws -> Resident {
        try living("Mika", minute: MovedIn.mika, profile: Resident.Profile(
            ageGroup: "thirties",
            occupation: "baker",
            hobby: "fishing",
            worry: "the rent",
            personality: "cheerful",
        ))
    }

    static func jun() throws -> Resident {
        try living("Jun", minute: MovedIn.jun, profile: Resident.Profile(
            ageGroup: "twenties",
            occupation: "librarian",
            hobby: "chess",
            worry: "a leaky roof",
            personality: "shy",
        ))
    }

    static func aki() throws -> Resident {
        try living("Aki", minute: MovedIn.aki, profile: Resident.Profile(
            ageGroup: "sixties",
            occupation: "postman",
            hobby: "gardening",
            worry: "his knees",
            personality: "gruff",
        ))
    }

    static func ren() throws -> Resident {
        try living("Ren", minute: MovedIn.ren, profile: Resident.Profile(
            ageGroup: "teens",
            occupation: "student",
            hobby: "drawing",
            worry: "exams",
            personality: "curious",
        ))
    }

    /// Sora, who moved out the minute she moved in.
    static func sora() throws -> Resident {
        let movedIn = StoreFixtures.minutes(MovedIn.sora)
        return try Resident(
            id: Resident.ID(),
            name: "Sora",
            profile: Resident.Profile(
                ageGroup: "forties",
                occupation: "florist",
                hobby: "running",
                worry: "the shop",
                personality: "warm",
            ),
            movedInAt: movedIn,
            status: .movedOut,
            movedOutAt: movedIn,
        )
    }

    private static func living(
        _ name: String,
        minute: Int,
        profile: Resident.Profile,
    ) throws -> Resident {
        try Resident(
            id: Resident.ID(),
            name: name,
            profile: profile,
            movedInAt: StoreFixtures.minutes(minute),
        )
    }
}

/// How an engine suite's town and engine start.
struct EngineSetup {
    /// The seed every literal expected time is worked out for.
    static let seed: UInt64 = 42

    var residents: [Resident]
    /// When the next ordinary scene is due.
    var due = EngineFixtures.start
    /// Posts stored before the engine starts.
    var priorPosts: [Post] = []
    var outcomes: [FakeLanguageModelProvider.Outcome] = []
    var holdsResponses = false
    var availability = ModelAvailability.available
    var speed = Speed.normal
    var displayName: String? = "Tomo"
    var thermalState = ThermalState.nominal
    var generator: any RandomNumberGenerator & Sendable = SplitMix64(seed: Self.seed)
    var tuning = Tuning.default

    /// A town of Mika alone, so every scene is hers whatever is drawn.
    static func mikaAlone() throws -> Self {
        try Self(residents: [EngineCast.mika()])
    }
}

/// One engine over a founded store, a fake model, a manual clock whose start is
/// ``EngineFixtures/start``, and its own settings suite.
struct EngineHarness {
    /// More posts than any test stores.
    private static let readLimit = 1_000

    let engine: TownEngine
    let store: TownStore
    let directory: TownDirectory
    let model: FakeLanguageModelProvider
    let clock: ManualClock
    let thermal: ThermalReading
    let defaults: UserDefaults
    let residents: [Resident]

    var settings: SettingsStore {
        SettingsStore(defaults: defaults)
    }

    /// The posts stored at or before 12:00, newest first.
    func storedPosts() async throws -> [Post] {
        try await store.recentPosts(before: EngineFixtures.noon, limit: Self.readLimit)
    }

    /// When the next ordinary scene is due, as stored.
    func storedDue() async throws -> Date {
        try #require(await store.schedule()).nextOrdinarySceneDue
    }
}

/// Values the engine suites share.
enum EngineFixtures {
    /// 2026-10-01T10:06:00Z — every engine test starts its clock here.
    static let start = StoreFixtures.date("2026-10-01T10:06:00Z")
    /// 2026-10-01T12:00:00Z, after every post a test writes.
    static let noon = StoreFixtures.date("2026-10-01T12:00:00Z")

    private static let millisecondsPerSecond = 1_000.0

    /// The time `clock` names on 2026-10-01 in UTC, "10:07:12.345", exactly as the store
    /// reads back a time it kept to the millisecond.
    static func time(_ clock: String) -> Date {
        let pieces = clock.split(separator: ".")
        let whole = StoreFixtures.date("2026-10-01T\(pieces.first ?? "")Z")
        let milliseconds = pieces.dropFirst().first.flatMap { Double($0) } ?? 0
        let total = whole.timeIntervalSince1970 * millisecondsPerSecond + milliseconds
        return Date(timeIntervalSince1970: total / millisecondsPerSecond)
    }

    /// Whether a step stored a scene.
    static func isStored(_ outcome: EngineStep) -> Bool {
        if case .sceneStored = outcome {
            return true
        }
        return false
    }

    /// The model's answer: `posts` by `speaker`, the second and later replying to the
    /// first, tagged `tags`.
    static func scene(by speaker: String, _ texts: [String], tags: [String]) -> GeneratedContent {
        let posts = texts.enumerated().map { index, text in
            DraftPost(speaker: speaker, text: text, replyTo: index == 0 ? nil : "S1")
        }
        return WritingFixtures.content(posts, tags: tags)
    }

    /// The founded town a setup describes: an ended founding event, the schedule due at
    /// `setup.due`, and `setup.priorPosts` as its first scene.
    static func founding(_ setup: EngineSetup) throws -> TownStore.FoundingStep {
        try TownStore.FoundingStep(
            town: WritingFixtures.town(),
            residents: setup.residents,
            foundingEvent: TownEvent(
                id: TownEvent.ID(),
                kind: .founding,
                description: "You moved to Maplewood.",
                startsAt: StoreFixtures.morning,
                endsAt: StoreFixtures.morning,
                status: .ended,
            ),
            schedule: Schedule(nextOrdinarySceneDue: setup.due, lastRanAt: StoreFixtures.morning),
            firstScene: TownStore.SceneStep(posts: setup.priorPosts),
        )
    }

    /// The speakers a prompt lists, by name, in order.
    static func speakers(in prompt: String) -> [String] {
        let lines = prompt.split(separator: "\n").map(String.init)
        guard let header = lines.firstIndex(of: "Speakers:") else {
            return []
        }
        return lines[(header + 1)...]
            .prefix { $0.hasPrefix("- ") }
            .compactMap { line in
                line.dropFirst("- ".count).split(separator: ":").first.map(String.init)
            }
    }

    /// The seed line of a prompt.
    static func seed(in prompt: String) -> String? {
        prompt.split(separator: "\n").map(String.init).first { $0.hasPrefix("Seed: ") }
    }
}

/// An engine over `store` and `model`, reading `clock` and `thermal`, with settings of its
/// own over the suite named `suite` — its own instance, since the engine keeps its
/// settings.
private func makeEngine(
    _ setup: EngineSetup,
    store: TownStore,
    model: FakeLanguageModelProvider,
    world: (clock: ManualClock, thermal: ThermalReading),
    suite: String,
) throws -> TownEngine {
    let start = EngineFixtures.start
    let (clock, thermal) = world
    return try TownEngine(
        parts: TownEngine.Parts(
            store: store,
            writer: SceneWriter(model: model, store: store, tuning: setup.tuning),
            settings: SettingsStore(defaults: #require(UserDefaults(suiteName: suite))),
            seedTables: SeedTables.load(),
            model: model,
        ),
        world: TownEngine.World(
            thermalState: { thermal.current },
            clock: clock,
            now: { start.addingTimeInterval(clock.elapsed / .seconds(1)) },
            generator: setup.generator,
        ),
        tuning: setup.tuning,
    )
}

/// Runs `body` with an engine set up as `setup` says, on a directory and a settings suite
/// of its own, both removed afterwards.
func withEngine(_ setup: EngineSetup, _ body: (EngineHarness) async throws -> Void) async throws {
    let suite = "EngineTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsStore(defaults: defaults)
    settings.speed = setup.speed
    settings.displayName = try setup.displayName.map { try DisplayName($0) }
    try await withStore { store, directory in
        try await store.found(EngineFixtures.founding(setup))
        let model = FakeLanguageModelProvider(
            availability: setup.availability,
            contextSize: WritingFixtures.roomyContextSize,
            outcomes: setup.outcomes,
            holdsResponses: setup.holdsResponses,
        )
        let clock = ManualClock()
        let thermal = ThermalReading(setup.thermalState)
        let engine = try makeEngine(
            setup,
            store: store,
            model: model,
            world: (clock, thermal),
            suite: suite,
        )
        try await body(EngineHarness(
            engine: engine,
            store: store,
            directory: directory,
            model: model,
            clock: clock,
            thermal: thermal,
            defaults: defaults,
            residents: setup.residents,
        ))
    }
}
