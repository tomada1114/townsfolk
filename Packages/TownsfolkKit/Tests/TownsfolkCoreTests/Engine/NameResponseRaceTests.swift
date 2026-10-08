import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("First response name races")
struct NameResponseRaceTests {
    @Test
    func `a prior reply arriving during generation consumes extraction atomically`() async throws {
        var setup = try EngineInterestExtractionTests.setup(names: [["Rust"]])
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let source = try EngineInterestExtractionTests.source(
                "Rust",
                at: EngineFixtures.time("09:40:00"),
            )
            try await EngineInterestExtractionTests.queue(source, harness: harness)
            let engine = harness.engine
            let task = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            let previous = try EngineResponseFixtures.answered(source, by: harness.residents[0].id)
            try await harness.store.storeScene(.init(posts: [previous]))
            try await harness.store.excludePost(previous.id)
            harness.model.releaseHeld()
            #expect(try await EngineFixtures.isStored(task.value))
            #expect(try await harness.store.interests().isEmpty)
            #expect(try await harness.store.schedule()?.pendingResponses.isEmpty == true)
            #expect(harness.model.calls.count == 1)
        }
    }

    @Test
    func `an existing source link is not counted twice`() async throws {
        let setup = try EngineInterestExtractionTests.setup(names: [["Rust"]])
        try await withEngine(setup) { harness in
            let source = try EngineInterestExtractionTests.source(
                "Rust",
                at: EngineFixtures.time("09:40:00"),
            )
            try await EngineInterestExtractionTests.queue(source, harness: harness)
            let interest = try Interest(
                id: Interest.ID(),
                term: "Rust",
                firstMentionedAt: source.happenedAt,
                lastMentionedAt: source.happenedAt,
                mentions: 1,
                sourcePosts: [source.id],
            )
            try await harness.store.storeScene(.init(posts: [], interests: [interest]))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.store.interests() == [interest])
        }
    }
}
