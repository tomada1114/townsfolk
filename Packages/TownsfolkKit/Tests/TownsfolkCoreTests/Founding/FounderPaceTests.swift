import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// The first ordinary scene waits a full interval after the founding scene (#73).
@Suite("Founder, first scene pace")
struct FounderPaceTests {
    @Test(arguments: [0.0, 0.0004])
    func `a seeded normal interval starts at the first scene's last post`(
        offset: Double,
    ) async throws {
        try await withStore { store, _ in
            var answers = Array(FoundingFixtures.happyPath.prefix(4))
            answers.append(.scene([
                DraftPost(speaker: "Jun", text: "The library is open."),
                DraftPost(speaker: "Jun", text: "Come by tomorrow.", replyTo: "S1"),
            ]))
            let fake = FoundingFixtures.fake(answers)
            let founder = try Founder(
                model: fake,
                writer: SceneWriter(model: fake, store: store),
                seeds: FoundingFixtures.tables(),
                store: store,
                now: { FoundingFixtures.now.addingTimeInterval(offset) },
                generator: FoundingFixtures.SplitMix(seed: 1),
            )
            try #require(try await found(with: founder) == .founded)

            let schedule = try #require(try await store.schedule())
            // Seed 1 draws raw 0x87b341d690d7a28a for the interval after casting:
            // its top 53 bits give 370.82843910057204 s, stored to milliseconds.
            let due = Date(timeIntervalSince1970: 1_790_849_170.828)
            #expect(schedule.nextOrdinarySceneDue == due)
            let posts = try await timeline(in: store).compactMap { entry -> Post? in
                if case let .post(post) = entry {
                    return post
                }
                return nil
            }
            #expect(posts.first?.happenedAt == FoundingFixtures.now)
            #expect((180 ... 540)
                .contains(schedule.nextOrdinarySceneDue.timeIntervalSince(FoundingFixtures.now)))
        }
    }

    @Test
    func `the engine's first step waits after founding without making another model call`(
    ) async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            try #require(try await found(with: founder(fake, store: store)) == .founded)
            let suite = "FounderPaceTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let engine = try TownEngine(
                parts: TownEngine.Parts(
                    store: store,
                    writer: SceneWriter(model: fake, store: store),
                    settings: SettingsStore(defaults: #require(UserDefaults(suiteName: suite))),
                    seedTables: FoundingFixtures.tables(),
                    model: fake,
                ),
                world: TownEngine.World(thermalState: { .nominal }, now: { FoundingFixtures.now }),
            )

            let due = FoundingFixtures.now.addingTimeInterval(180)
            #expect(try await engine.step() == .waiting(until: due))
            #expect(fake.calls.count == 5)
            #expect(try await store.schedule()?.nextOrdinarySceneDue == due)
            #expect(try await timeline(in: store).count == 3)
        }
    }

    @Test(arguments: [(Speed.fast, 30.0), (.normal, 180.0), (.slow, 900.0)])
    func `the selected speed sets the first scene interval`(
        speed: Speed,
        seconds: Double,
    ) async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let founder = try founder(fake, store: store)
            let outcome = try await founder
                .found(displayName: DisplayName("Tomo"), speed: speed) { _ in
                    // Progress is checked in FounderTests; only the stored due matters here.
                }
            try #require(outcome == .founded)
            #expect(try await store.schedule()?.nextOrdinarySceneDue == FoundingFixtures.now
                .addingTimeInterval(seconds))
        }
    }

    @Test
    func `a nondefault pace tuning applies to the first interval`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            var tuning = Tuning.default
            tuning.pace.sceneInterval.normal = .seconds(12)
            tuning.pace.sceneIntervalJitter = 0
            let founder = try Founder(
                model: fake,
                writer: SceneWriter(model: fake, store: store, tuning: tuning),
                seeds: FoundingFixtures.tables(),
                store: store,
                now: { FoundingFixtures.now },
                generator: FoundingFixtures.FirstChoice(),
                tuning: tuning,
            )
            try #require(try await found(with: founder) == .founded)
            #expect(try await store.schedule()?.nextOrdinarySceneDue == FoundingFixtures.now
                .addingTimeInterval(12))
        }
    }

    @MainActor
    @Test
    func `the founding screen passes its selected speed to the founder`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let model = try FoundingViewModel(
                displayName: DisplayName("Tomo"),
                founder: founder(fake, store: store),
                store: store,
                speed: .fast,
            )
            try await model.run()
            #expect(model.phase == .arrived)
            #expect(try await store.schedule()?.nextOrdinarySceneDue == FoundingFixtures.now
                .addingTimeInterval(30))
        }
    }
}
