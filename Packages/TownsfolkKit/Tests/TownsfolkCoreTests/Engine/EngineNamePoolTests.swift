import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Name seed pools")
struct EngineNamePoolTests {
    struct Pick: Sendable {
        let draw: Double
        let seed: String
    }

    @Test(arguments: [
        Pick(draw: 0.125, seed: "Seed: Mika's occupation: baker."),
        Pick(draw: 0.375, seed: "Seed: the topic \"rain\", still going."),
        Pick(draw: 0.625, seed: "Seed: the ongoing event \"It started raining.\""),
        Pick(draw: 0.875, seed: "Seed: Rust, a name Tomo brought up."),
    ])
    func `each nonempty kind has one uniform quarter`(_ pick: Pick) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup
            .priorPosts =
            try [ResidentPostDraft(author: setup.residents[0].id, topicTags: ["rain"]).make()]
        setup.priorEvents = try [EventDraft(time: EngineFixtures.start).make()]
        setup.outcomes = WritingFixtures.refusals(3)
        setup.generator = ScriptedGenerator([pick.draw, 0])
        try await withEngine(setup) { harness in
            let name = try EngineInterestUptakeTests.name("Rust")
            try await harness.store.storeScene(.init(posts: [], interests: [name]))
            _ = try await harness.engine.step()
            #expect(try EngineFixtures.seed(in: #require(harness.model.calls.first).prompt) == pick
                .seed)
        }
    }

    @Test
    func `names appear in refusal retries and excluded names never appear`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.outcomes = WritingFixtures.refusals(3)
        // First profile, then name retry, then remaining profile.
        setup.generator = ScriptedGenerator([0, 0, 0, 0.75, 0, 0, 0])
        try await withEngine(setup) { harness in
            let name = try EngineInterestUptakeTests.name("Rust")
            let excluded = try EngineInterestUptakeTests.name("Excluded")
            try await harness.store.storeScene(.init(posts: [], interests: [name, excluded]))
            try await harness.store.excludeInterest(excluded.id)
            _ = try await harness.engine.step()
            let seeds = harness.model.calls.compactMap { EngineFixtures.seed(in: $0.prompt) }
            #expect(seeds.contains("Seed: Rust, a name Tomo brought up."))
            #expect(!harness.model.calls.contains { $0.prompt.contains("Excluded") })
        }
    }
}
