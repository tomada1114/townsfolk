import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Town response seeds")
struct EngineResponseSeedTests {
    @Test(arguments: [
        (UInt64(1), ["10:12:31.950", "11:04:26.975"]),
        (UInt64(4), ["10:11:27.099", "10:38:16.627", "10:58:18.904"]),
    ])
    func `weighted schedules`(seed: UInt64, due: [String]) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = SplitMix64(seed: seed)
        setup.due = EngineFixtures.noon
        try await withEngine(setup) { harness in
            try await harness.store.storeYourPost(EngineResponseFixtures.post())
            _ = try await harness.engine.step()
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.dueAt) == due
                .map(EngineFixtures.time))
        }
    }

    @Test(arguments: [0.0, 0.699, 0.7, 0.999])
    func `lead chance`(roll: Double) async throws {
        var setup = try EngineSetup.mikaAlone()
        // 2 scheduling draws, 7 ordinary casting draws, then the lead chance.
        setup.generator = ScriptedGenerator(Array(repeating: 0, count: 9) + [roll])
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        let target = try ResidentPostDraft(
            author: setup.residents[0].id,
            time: EngineFixtures.time("10:00:00"),
        ).make()
        setup.priorPosts = [target]
        try await withEngine(setup) { harness in
            try await harness.store.storeYourPost(EngineResponseFixtures.post(
                at: EngineFixtures.time("10:00:01"),
                reply: target.id,
            ))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let seed = try #require(harness.model.calls.first
                .flatMap { EngineFixtures.seed(in: $0.prompt) })
            #expect(seed.contains("The first post replies to it."))
            #expect(seed.contains("Mika writes the first post.") == (roll < 0.7))
        }
    }

    @Test(arguments: [false, true])
    func `later has no lead`(ownTarget: Bool) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let target: Post
            if ownTarget {
                target = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
                try await harness.store.storeYourPost(target)
            } else {
                target = try ResidentPostDraft(
                    author: harness.residents[0].id,
                    time: EngineFixtures.time("10:00:00"),
                ).make()
                try await harness.store.storeScene(.init(posts: [target]))
            }
            let post = try EngineResponseFixtures.post(
                at: EngineFixtures.time("10:00:01"),
                reply: target.id,
            )
            try await harness.store.storeYourPost(post)
            if !ownTarget {
                let first = try EngineResponseFixtures.answered(post, by: harness.residents[0].id)
                try await harness.store.storeScene(.init(posts: [first]))
            }
            let pending = Schedule.PendingResponse(
                post: post.id,
                dueAt: EngineFixtures.time("10:05:00"),
            )
            try await harness.store.updatePendingResponses(adding: [pending])
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let seed = try #require(harness.model.calls.first
                .flatMap { EngineFixtures.seed(in: $0.prompt) })
            #expect(!seed.contains("writes the first post."))
        }
    }

    @Test(arguments: [0.0, 86_400.0, 86_401.0])
    func `coming back window`(age: Double) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.yourPost.postSeedChance = 1
        setup.generator = RepeatingGenerator(value: 0)
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures
                .post(at: EngineFixtures.start.addingTimeInterval(-age))
            try await harness.store.storeYourPost(post)
            let answered = try EngineResponseFixtures.answered(post, by: harness.residents[0].id)
            try await harness.store.storeScene(.init(posts: [answered]))
            let result = try await harness.engine.step()
            guard case let .sceneStored(ids, _) = result else {
                Issue.record("Expected an ordinary scene to be stored")
                return
            }
            #expect(!ids.isEmpty)
            let seed = try #require(harness.model.calls.first
                .flatMap { EngineFixtures.seed(in: $0.prompt) })
            #expect(seed.contains("Seed: what") == (age <= 86_400))
            #expect(!seed.contains("The first post replies to it."))
            #expect(harness.model.calls[0].prompt.contains("Bread today?") == (age <= 86_400))
            for id in ids {
                #expect(try await harness.store.post(id)?.origin == .ordinary)
            }
            #expect(try await harness.store.post(answered.id) == answered)
        }
    }

    @Test
    func `unanswered post cannot seed an ordinary scene before its delay`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.yourPost.postSeedChance = 1
        setup.generator = RepeatingGenerator(value: 0)
        let content = WritingFixtures.content([
            DraftPost(speaker: "Mika", text: "Rain today.", replyTo: "P1"),
        ])
        setup.outcomes = [.content(content)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post()
            try await harness.engine.submitYourPost(post, speed: .normal)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let seed = try #require(harness.model.calls.first
                .flatMap { EngineFixtures.seed(in: $0.prompt) })
            #expect(!seed.contains("Seed: what"))
            #expect(!harness.model.calls[0].prompt.contains("Bread today?"))
            #expect(try await harness.storedPosts().first?.replyTarget == nil)
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.post) == [post.id])
        }
    }

    @Test
    func `refusals never stall`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.outcomes = WritingFixtures.refusals(9) + [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
            try await harness.store.storeYourPost(post)
            for _ in 0 ..< 3 {
                _ = try await harness.engine.step()
                harness.clock.advance(by: .seconds(180))
            }
            #expect(harness.model.calls.count == 9)
            #expect(try await harness.store.schedule()?.pendingResponses.isEmpty == true)
            harness.clock.advance(by: .seconds(180))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let seed = try #require(harness.model.calls.last
                .flatMap { EngineFixtures.seed(in: $0.prompt) })
            #expect(!seed.contains("Bread today?"))
            #expect(try await harness.store.post(post.id) == post)
        }
    }

    @Test
    func `displaced profile owner never seeds response retry`() async throws {
        var setup = try EngineSetup(residents: [EngineCast.mika(), EngineCast.jun()])
        setup.generator = RepeatingGenerator(value: 0)
        let target = try ResidentPostDraft(
            author: setup.residents[1].id,
            time: EngineFixtures.time("10:00:00"),
        ).make()
        setup.priorPosts = [target]
        let fallback = EngineFixtures.scene(by: "Jun", ["The library is quiet."], tags: [])
        setup.outcomes = [.failure(.refused), .failure(.refused), .content(fallback)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(
                at: EngineFixtures.time("10:00:01"),
                reply: target.id,
            )
            try await harness.store.storeYourPost(post)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(harness.model.calls.count == 3)
            for call in harness.model.calls.dropFirst() {
                #expect(EngineFixtures.speakers(in: call.prompt) == ["Jun"])
                let seed = try #require(EngineFixtures.seed(in: call.prompt))
                #expect(seed.contains("Jun's"))
                #expect(!seed.contains("Mika's"))
            }
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.post) == [post.id])
        }
    }
}
