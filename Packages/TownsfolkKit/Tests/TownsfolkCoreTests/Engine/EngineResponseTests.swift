import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Town responses")
struct EngineResponseTests {
    @Test(arguments: [(Speed.fast, "10:07:00"), (.normal, "10:08:00"), (.slow, "10:10:00")])
    func earliest(speed: Speed, due: String) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.generator = RepeatingGenerator(value: 0)
        setup.speed = speed
        setup.due = EngineFixtures.noon
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post()
            try await harness.store.storeYourPost(post)
            _ = try await harness.engine.step()
            #expect(try await harness.store.schedule()?.pendingResponses == [
                Schedule.PendingResponse(post: post.id, dueAt: EngineFixtures.time(due)),
            ])
        }
    }

    @Test(arguments: [(Speed.normal, "10:16:00"), (.slow, "10:26:00")])
    func latest(speed: Speed, due: String) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.generator = RepeatingGenerator(value: .max)
        setup.speed = speed
        setup.due = EngineFixtures.noon
        try await withEngine(setup) { harness in
            try await harness.store.storeYourPost(EngineResponseFixtures.post())
            _ = try await harness.engine.step()
            let responses = try #require(await harness.store.schedule()).pendingResponses
            #expect(responses.count == 3)
            #expect(responses.first?.dueAt == EngineFixtures.time(due))
        }
    }

    @Test
    func `response before ordinary`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.generator = RepeatingGenerator(value: 0)
        setup.due = EngineFixtures.noon
        let scene = EngineFixtures.scene(by: "Mika", ["Fresh bread."], tags: ["bread"])
        setup.outcomes = [.content(scene)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
            try await harness.store.storeYourPost(post)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let response = try #require(try await harness.storedPosts().first { $0.author != .you })
            #expect(response.origin == .response)
            #expect(response.replyTarget == post.id)
            #expect(response.topicTags == ["bread"])
            #expect(try await harness.store.schedule()?.pendingResponses.isEmpty == true)
        }
    }

    @Test
    func `exclusions drop pending`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.due = EngineFixtures.noon
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post()
            try await harness.store.storeYourPost(post)
            let pending = Schedule.PendingResponse(post: post.id, dueAt: EngineFixtures.start)
            try await harness.store.updatePendingResponses(adding: [pending])
            try await harness.store.excludePost(post.id)
            _ = try await harness.engine.step()
            #expect(try await harness.store.schedule()?.pendingResponses.isEmpty == true)
        }
    }
}
