import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Town response recovery")
struct EngineResponseRecoveryTests {
    @Test
    func `seeded schedule`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.due = EngineFixtures.noon
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post()
            try await harness.store.storeYourPost(post)
            _ = try await harness.engine.step()
            #expect(try await harness.store.schedule()?.pendingResponses == [
                .init(post: post.id, dueAt: EngineFixtures.time("10:13:55.951")),
            ])
            _ = try await harness.engine.step()
            #expect(try await harness.store.schedule()?.pendingResponses.count == 1)
        }
    }

    @Test
    func cap() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.due = EngineFixtures.noon
        setup.generator = RepeatingGenerator(value: 0)
        try await withEngine(setup) { harness in
            var posts: [Post] = []
            for second in 0 ..< 4 {
                let post = try EngineResponseFixtures
                    .post(at: EngineFixtures.start.addingTimeInterval(Double(second)))
                posts.append(post)
                try await harness.store.storeYourPost(post)
                _ = try await harness.engine.step()
                #expect(try await harness.store.schedule()?.pendingResponses.count == min(
                    second + 1,
                    3,
                ))
            }
            #expect(try await harness.store.schedule()?.pendingResponses
                .map(\.post) == Array(posts.dropFirst()).map(\.id))
        }
    }

    @Test
    func `alternate retains response`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.generator = RepeatingGenerator(value: 0)
        setup.outcomes = [.failure(.refused), .content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
            try await harness.store.storeYourPost(post)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(harness.model.calls.count == 2)
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.post) == [post.id])
            let residentPosts = try await harness.storedPosts().filter { $0.author != .you }
            #expect(residentPosts.allSatisfy { $0.origin == .ordinary })
        }
    }

    @Test
    func `response rollback`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.generator = RepeatingGenerator(value: 0)
        setup.due = EngineFixtures.noon
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post()
            try await harness.store.storeYourPost(post)
            _ = try await harness.engine.step()
            let raw = try harness.directory.raw()
            try raw.execute(EngineFailureTests.refuseReplies)
            let before = try raw.snapshot()
            harness.clock.advance(by: .seconds(120))
            #expect(try await harness.engine.step() == .failed(EngineFailureTests.refusedByTrigger))
            #expect(try raw.snapshot() == before)
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.post) == [post.id])
        }
    }

    @Test(arguments: [ThermalState.serious, .critical])
    func `hot waits`(heat: ThermalState) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.thermalState = heat
        setup.generator = RepeatingGenerator(value: 0)
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
            try await harness.store.storeYourPost(post)
            _ = try await harness.engine.step()
            #expect(harness.model.calls.isEmpty)
            #expect(try await harness.store.schedule()?.pendingResponses.count == 1)
            harness.thermal.current = .nominal
            harness.clock.advance(by: .seconds(180))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.store.schedule()?.pendingResponses.isEmpty == true)
        }
    }

    @Test
    func `unavailable overdue earliest first`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.availability = .modelNotReady
        setup.outcomes = [
            .content(WritingFixtures.mikaSpeaks),
            .content(WritingFixtures.mikaSpeaks),
        ]
        setup.generator = RepeatingGenerator(value: 0)
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
            try await harness.store.storeYourPost(post)
            let early = Schedule.PendingResponse(
                post: post.id,
                dueAt: EngineFixtures.time("10:01:00"),
            )
            let late = Schedule.PendingResponse(
                post: post.id,
                dueAt: EngineFixtures.time("10:02:00"),
            )
            try await harness.store.updatePendingResponses(adding: [late, early])
            #expect(try await harness.engine.step() == .modelUnavailable)
            #expect(try await harness.store.schedule()?.pendingResponses == [early, late])
            harness.model.availability = .available
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.store.schedule()?.pendingResponses == [late])
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.store.schedule()?.pendingResponses.isEmpty == true)
            #expect(harness.model.highestInFlight == 1)
        }
    }

    @Test
    func `no interleaving`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.generator = RepeatingGenerator(value: 0)
        setup.outcomes = [
            .content(EngineFixtures.scene(by: "Mika", ["First.", "Second."], tags: [])),
            .content(WritingFixtures.mikaSpeaks),
        ]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
            try await harness.store.storeYourPost(post)
            try await harness.store.updatePendingResponses(adding: [
                .init(post: post.id, dueAt: EngineFixtures.time("10:01:00")),
                .init(post: post.id, dueAt: EngineFixtures.time("10:02:00")),
            ])
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.engine
                .step() == .waiting(until: EngineFixtures.time("10:06:36")))
            #expect(harness.model.calls.count == 1)
            harness.clock.advance(by: .seconds(36))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
        }
    }
}
