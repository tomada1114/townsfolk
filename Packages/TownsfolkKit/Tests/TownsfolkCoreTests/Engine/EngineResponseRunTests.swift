import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Town responses while running")
struct EngineResponseRunTests {
    @Test
    func `committed post rearms wait`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.due = EngineFixtures.noon
        setup.holdsResponses = true
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let engine = harness.engine
            let run = Task { try await engine.run() }
            await harness.clock.waitForSleepers(count: 1)
            #expect(harness.clock.nextDeadline == .seconds(6_840))
            let post = try EngineResponseFixtures.post()
            try await harness.store.storeYourPost(post)
            await harness.clock.waitForDeadline(.seconds(120))
            #expect(try await harness.store.schedule()?.pendingResponses.first?
                .dueAt == EngineFixtures.time("10:08:00"))
            harness.clock.advance(by: .seconds(120))
            await harness.model.waitUntilHeld(count: 1)
            #expect(harness.model.highestInFlight == 1)
            run.cancel()
            await #expect(throws: CancellationError.self) { try await run.value }
            #expect(harness.clock.sleeperCount == 0)
            #expect(try await harness.store.schedule()?.pendingResponses.count == 1)
        }
    }

    @Test
    func `speed change keeps response dates`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.due = EngineFixtures.noon
        try await withEngine(setup) { harness in
            try await harness.store.storeYourPost(EngineResponseFixtures.post())
            _ = try await harness.engine.step()
            let before = try await harness.store.schedule()?.pendingResponses
            harness.settings.speed = .fast
            _ = await harness.engine.speedChanged()
            #expect(try await harness.store.schedule()?.pendingResponses == before)
        }
    }

    @Test
    func `moved away has no lead`() async throws {
        let sora = try EngineCast.sora()
        var setup = try EngineSetup(residents: [EngineCast.mika(), sora])
        setup.generator = RepeatingGenerator(value: 0)
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        let target = try ResidentPostDraft(author: sora.id, time: EngineFixtures.time("10:00:00"))
            .make()
        setup.priorPosts = [target]
        try await withEngine(setup) { harness in
            try await harness.store.storeYourPost(EngineResponseFixtures.post(
                at: EngineFixtures.time("10:00:01"),
                reply: target.id,
            ))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let seed = try #require(harness.model.calls.first
                .flatMap { EngineFixtures.seed(in: $0.prompt) })
            #expect(!seed.contains("writes the first post."))
            #expect(EngineFixtures.speakers(in: harness.model.calls[0].prompt) == ["Mika"])
        }
    }

    @Test
    func `excluded during model call is discarded`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.holdsResponses = true
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
            try await harness.store.storeYourPost(post)
            let engine = harness.engine
            let step = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            try await harness.store.excludePost(post.id)
            harness.model.releaseHeld()
            let result = try await step.value
            #expect(!EngineFixtures.isStored(result))
            #expect(try await harness.store.schedule()?.pendingResponses.isEmpty == true)
            #expect(try await harness.storedPosts().isEmpty)
            #expect(try await harness.store.post(post.id) == post)
        }
    }

    @Test
    func `future response is not delayed by ordinary success`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.tuning.yourPost.postSeedChance = 0
        setup.outcomes = [
            .content(WritingFixtures.mikaSpeaks),
            .content(WritingFixtures.mikaSpeaks),
        ]
        try await withEngine(setup) { harness in
            try await harness.store.storeYourPost(EngineResponseFixtures.post())
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.engine
                .step() == .waiting(until: EngineFixtures.time("10:08:00")))
        }
    }
}
