import Foundation
import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Town interest extraction")
struct EngineInterestExtractionTests {
    static func setup(names: [[String]]) throws -> EngineSetup {
        var setup = try EngineSetup.mikaAlone()
        setup.tuning.events.maxOngoingEvents = 0
        setup.tuning.residents.population = 1 ... 1
        setup.generator = RepeatingGenerator(value: 0)
        setup.outcomes = names.map { .content(content($0)) }
        return setup
    }

    static func content(_ names: [String]) -> GeneratedContent {
        SceneDraft(
            posts: [.init(speaker: "Mika", text: "Rain again.", replyTo: nil)],
            topicTags: ["rain"],
            names: names,
        ).generatedContent
    }

    static func source(_ text: String, at time: Date) throws -> Post {
        try Post(id: Post.ID(), author: .you, text: text, happenedAt: time)
    }

    static func queue(_ post: Post, harness: EngineHarness) async throws {
        try await harness.store.storeYourPost(post)
        try await harness.store.updatePendingResponses(adding: [
            .init(post: post.id, dueAt: EngineFixtures.time("10:01:00")),
        ])
    }

    @Test(arguments: [false, true])
    func `case insensitive merge preserves spelling and chronological source bounds`(
        reversed: Bool,
    ) async throws {
        let setup = try Self.setup(names: [["Rust"], ["rust"]])
        try await withEngine(setup) { harness in
            let early = EngineFixtures.time("09:40:00")
            let late = EngineFixtures.time("09:50:00")
            let first = try Self.source("Rust", at: reversed ? late : early)
            let second = try Self.source("rust", at: reversed ? early : late)
            try await Self.queue(first, harness: harness)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let original = try #require(await harness.store.interests().first)
            try await Self.queue(second, harness: harness)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let interests = try await harness.store.interests()
            #expect(interests.count == 1)
            let merged = try #require(interests.first)
            #expect(merged.id == original.id)
            #expect(merged.term == "Rust")
            #expect(merged.mentions == 2)
            #expect(merged.sourcePosts == [first.id, second.id])
            #expect(merged.firstMentionedAt == early)
            #expect(merged.lastMentionedAt == late)
            #expect(harness.model.calls.count == 2)
            #expect(try harness.directory.raw().userVersion() == 1)
        }
    }

    @Test
    func `excluded term stays excluded when mentioned in another source`() async throws {
        let setup = try Self.setup(names: [["Rust"], ["rust"]])
        try await withEngine(setup) { harness in
            let first = try Self.source("Rust", at: EngineFixtures.time("09:40:00"))
            try await Self.queue(first, harness: harness)
            _ = try await harness.engine.step()
            let original = try #require(await harness.store.interests().first)
            try await harness.store.excludeInterest(original.id)
            let second = try Self.source("rust", at: EngineFixtures.time("09:50:00"))
            try await Self.queue(second, harness: harness)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.store.interests().isEmpty)
            let raw = try harness.directory.raw()
            let rows = try raw.rows("SELECT term, mentions, excluded FROM interests")
            #expect(rows == [["Rust", "2", "1"]])
            #expect(try raw.count("interest_source_posts") == 2)
        }
    }

    @Test
    func `empty first success consumes extraction opportunity`() async throws {
        let setup = try Self.setup(names: [[], ["Rust"]])
        try await withEngine(setup) { harness in
            let post = try Self.source("Rust", at: EngineFixtures.time("09:40:00"))
            try await Self.queue(post, harness: harness)
            try await harness.store.updatePendingResponses(adding: [
                .init(post: post.id, dueAt: EngineFixtures.time("10:02:00")),
            ])
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.store.interests().isEmpty)
            #expect(harness.model.calls.count == 2)
        }
    }

    @Test
    func `refusal fallback keeps extraction for the subsequent first response`() async throws {
        var setup = try Self.setup(names: [["Rust"], ["Rust"]])
        setup.outcomes.insert(.failure(.refused), at: 0)
        try await withEngine(setup) { harness in
            let post = try Self.source("Rust", at: EngineFixtures.time("09:40:00"))
            try await Self.queue(post, harness: harness)
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.store.interests().isEmpty)
            #expect(try await harness.store.schedule()?.pendingResponses.count == 1)
            harness.clock.advance(by: .seconds(600))
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            #expect(try await harness.store.interests().map(\.term) == ["Rust"])
            #expect(harness.model.calls.count == 3)
        }
    }
}
