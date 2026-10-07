import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Ordinary scenes on a schedule (REQ-002–REQ-005, requirements §3.4): a due step writes
/// one scene whose posts are revealed apart, and the next due time runs from its last post;
/// a skipped turn moves only the due time. Expected times are worked out by hand from
/// SplitMix64 seeded 42 — Mika alone draws 7 numbers for the cast, then one per gap
/// between posts, then the jitter (0.8399… after a 0.2601… gap, 1.3006… with no gap).
@Suite("Town engine schedule")
struct EngineScheduleTests {
    @Test
    func `a step at exactly the due time stores the scene, revealed apart, in one scene`(
    ) async throws {
        var setup = try EngineSetup.mikaAlone()
        let scene = EngineFixtures.scene(
            by: "Mika",
            ["Fresh bread.", "Come early."],
            tags: ["bread"],
        )
        setup.outcomes = [.content(scene)]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            let posts = try await harness.storedPosts().reversed()
            try #require(posts.count == 2)
            let first = try #require(posts.first)
            let second = try #require(posts.last)
            #expect(outcome == .sceneStored(
                posts: [first.id, second.id],
                nextDue: EngineFixtures.time("10:12:36.020"),
            ))
            #expect(first.happenedAt == EngineFixtures.time("10:06:00"))
            #expect(second.happenedAt == EngineFixtures.time("10:07:33.645"))
            #expect(try await harness.storedDue() == EngineFixtures.time("10:12:36.020"))
            #expect(posts.allSatisfy { $0.origin == .ordinary && $0.topicTags == ["bread"] })
            #expect(first.sceneID != nil && first.sceneID == second.sceneID)
            #expect(first.author == .resident(harness.residents[0].id))
            #expect(first.replyTarget == nil)
            #expect(second.replyTarget == first.id)
            #expect(harness.model.calls.count == 1)
        }
    }

    @Test
    func `a scene of one post measures the next due time from that post`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.outcomes = [.content(EngineFixtures.scene(by: "Mika", ["Rain."], tags: []))]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            let posts = try await harness.storedPosts()
            #expect(posts.map(\.happenedAt) == [EngineFixtures.time("10:06:00")])
            #expect(outcome == .sceneStored(
                posts: posts.map(\.id),
                nextDue: EngineFixtures.time("10:13:48.227"),
            ))
            #expect(try await harness.storedDue() == EngineFixtures.time("10:13:48.227"))
        }
    }

    @Test
    func `a turn the writer skips stores only a new due time from now`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.outcomes = WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            #expect(outcome == .skipped(
                .writer(.refused),
                nextDue: EngineFixtures.time("10:13:48.227"),
            ))
            #expect(harness.model.calls.count == 3)
            #expect(try await harness.storedPosts().isEmpty)
            #expect(try await harness.storedDue() == EngineFixtures.time("10:13:48.227"))
        }
    }

    @Test
    func `a step before the due time waits and writes nothing`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.due = EngineFixtures.time("10:06:00.001")
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            #expect(outcome == .waiting(until: EngineFixtures.time("10:06:00.001")))
            #expect(harness.model.calls.isEmpty)
            #expect(try await harness.storedDue() == EngineFixtures.time("10:06:00.001"))
        }
    }

    @Test
    func `without a display name the turn is skipped without a call`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.displayName = nil
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            #expect(outcome == .skipped(
                .noDisplayName,
                nextDue: EngineFixtures.time("10:13:26.963"),
            ))
            #expect(harness.model.calls.isEmpty)
        }
    }

    @Test
    func `with nobody living in town the turn is skipped without a call`() async throws {
        var setup = try EngineSetup(residents: [EngineCast.sora()])
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            #expect(outcome == .skipped(
                .noSpeakers,
                nextDue: EngineFixtures.time("10:13:26.963"),
            ))
            #expect(harness.model.calls.isEmpty)
        }
    }

    @Test
    func `with nobody living in town a topic still going does not cast a scene`(
    ) async throws {
        let sora = try EngineCast.sora()
        var setup = EngineSetup(residents: [sora])
        let flood = try ResidentPostDraft(
            author: sora.id,
            time: StoreFixtures.date("2026-10-01T09:30:00Z"),
            topicTags: ["the flood"],
        ).make()
        setup.priorPosts = [flood]
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            #expect(outcome == .skipped(
                .noSpeakers,
                nextDue: EngineFixtures.time("10:13:26.963"),
            ))
            #expect(harness.model.calls.isEmpty)
            #expect(try await harness.storedDue() == EngineFixtures.time("10:13:26.963"))
        }
    }

    @Test
    func `a store with no town founded does nothing`() async throws {
        try await withStore { store, _ in
            let model = WritingFixtures.fake([.content(WritingFixtures.mikaSpeaks)])
            let suite = "EngineTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let engine = try TownEngine(
                parts: TownEngine.Parts(
                    store: store,
                    writer: SceneWriter(model: model, store: store),
                    settings: SettingsStore(defaults: #require(UserDefaults(suiteName: suite))),
                    seedTables: SeedTables.load(),
                    model: model,
                ),
                world: TownEngine.World { .nominal },
            )

            #expect(try await engine.step() == .notFounded)
            #expect(await engine.speedChanged() == nil)
            #expect(model.calls.isEmpty)
        }
    }
}
