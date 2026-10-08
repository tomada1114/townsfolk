import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Town name seed uptake")
struct EngineInterestUptakeTests {
    static func name(_ term: String) throws -> Interest {
        try Interest(
            id: Interest.ID(),
            term: term,
            firstMentionedAt: StoreFixtures.morning,
            lastMentionedAt: StoreFixtures.morning,
            mentions: 1,
        )
    }

    @Test(arguments: [0, 1])
    func `each included name can seed an ordinary scene and becomes an actual speakers interest`(
        index: Int,
    ) async throws {
        var setup = try EngineInterestExtractionTests.setup(names: [[]])
        // Pools profile/name; then selected name; one speaker; its index; two profile retries;
        // pace; uptake.
        setup.generator = ScriptedGenerator([
            0.75,
            ChangeFixtures.pick(index, of: 2),
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        ])
        try await withEngine(setup) { harness in
            let first = try Self.name("Rust")
            let second = try Self.name("Manga")
            let excluded = try Self.name("Excluded")
            try await harness.store.storeScene(.init(
                posts: [],
                interests: [first, second, excluded],
            ))
            try await harness.store.excludeInterest(excluded.id)
            let names = try await harness.store.interests()
            let chosen = names[index]
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try EngineFixtures
                .seed(in: #require(harness.model.calls.first).prompt) ==
                "Seed: \(chosen.term), a name Tomo brought up.")
            #expect(try await harness.store.residents().first?.interests == [chosen.id])
            #expect(try await harness.store.interests() == names)
        }
    }

    @Test(arguments: [0, 1])
    func `uptake draws among distinct eligible actual speakers and leaves nonspeakers alone`(
        recipient: Int,
    ) async throws {
        var setup = try EngineSetup(residents: [
            EngineCast.mika(),
            EngineCast.jun(),
            EngineCast.aki(),
            EngineCast.sora(),
        ])
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 3 ... 3
        setup.generator = ScriptedGenerator([
            0.75,
            0,
            0.99,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            ChangeFixtures.pick(recipient, of: 2),
        ])
        let content = WritingFixtures.content([
            .init(speaker: "Jun", text: "Rain again."),
            .init(speaker: "Mika", text: "Fine day."),
            .init(speaker: "Jun", text: "Indeed."),
        ])
        setup.outcomes = [.content(content)]
        try await withEngine(setup) { harness in
            let name = try Self.name("Rust")
            try await harness.store.storeScene(.init(posts: [], interests: [name]))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let residents = try await harness.store.residents()
            let holders = residents.filter { $0.interests.contains(name.id) }.map(\.name)
            #expect(holders == [recipient == 0 ? "Jun" : "Mika"])
        }
    }

    @Test
    func `a refused response can fall back to a name without extracting or delivering`(
    ) async throws {
        var setup = try EngineInterestExtractionTests.setup(names: [["NewName"]])
        setup.generator = ScriptedGenerator([0.75, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        setup.outcomes.insert(.failure(.refused), at: 0)
        try await withEngine(setup) { harness in
            let name = try Self.name("Rust")
            try await harness.store.storeScene(.init(posts: [], interests: [name]))
            let source = try EngineInterestExtractionTests.source(
                "NewName",
                at: EngineFixtures.time("09:40:00"),
            )
            try await EngineInterestExtractionTests.queue(source, harness: harness)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(harness.model.calls.count == 2)
            #expect(try await harness.store.interests().map(\.term) == ["Rust"])
            #expect(try await harness.store.residents().first?.interests == [name.id])
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.post) == [source.id])
        }
    }

    @Test
    func `an excluded held name seed stores nothing`() async throws {
        var setup = try EngineInterestExtractionTests.setup(names: [[]])
        setup.generator = ScriptedGenerator([0.75, 0, 0, 0, 0, 0, 0, 0])
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let name = try Self.name("Rust")
            try await harness.store.storeScene(.init(posts: [], interests: [name]))
            let engine = harness.engine
            let task = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            try await harness.store.excludeInterest(name.id)
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let changes = await harness.store.changes()
            harness.model.releaseHeld()
            #expect(try await task.value == .waiting(until: EngineFixtures.start))
            #expect(try raw.snapshot() == before)
            try await harness.store.setLastRan(EngineFixtures.start)
            #expect(await firstChange(changes) == .lastRanChanged)
        }
    }
}
