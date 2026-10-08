import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Name extraction atomicity")
struct NameAtomicityTests {
    private static func existingName(harness: EngineHarness) async throws {
        let earlier = try EngineInterestExtractionTests.source(
            "Rust",
            at: EngineFixtures.time("09:30:00"),
        )
        try await harness.store.storeYourPost(earlier)
        let interest = try Interest(
            id: Interest.ID(),
            term: "Rust",
            firstMentionedAt: earlier.happenedAt,
            lastMentionedAt: earlier.happenedAt,
            mentions: 1,
            sourcePosts: [earlier.id],
        )
        let answer = try EngineResponseFixtures.answered(
            earlier,
            by: harness.residents[0].id,
        )
        try await harness.store.storeScene(.init(posts: [answer], interests: [interest]))
    }

    private static func withdraw(
        _ withdrawal: Int,
        post: Post.ID,
        harness: EngineHarness,
    ) async throws {
        switch withdrawal {
        case 0:
            for second in 0 ..< 3 {
                let newer = try EngineInterestExtractionTests.source(
                    "New",
                    at: EngineFixtures.start.addingTimeInterval(Double(second)),
                )
                try await harness.engine.submitYourPost(newer, speed: .normal)
            }

        case 1:
            try await harness.store.updatePendingResponses(
                adding: [.init(post: post, dueAt: EngineFixtures.noon)],
                droppingFor: [post],
            )

        default:
            try await harness.store.excludePost(post)
            try await harness.store.updatePendingResponses(adding: [], droppingFor: [post])
        }
    }

    @Test(arguments: [false, true])
    func `failure after name source write rolls back new and existing names`(
        existing: Bool,
    ) async throws {
        let setup = try EngineInterestExtractionTests.setup(names: [["Rust"]])
        try await withEngine(setup) { harness in
            let post = try EngineInterestExtractionTests.source(
                "Rust",
                at: EngineFixtures.time("09:40:00"),
            )
            try await EngineInterestExtractionTests.queue(post, harness: harness)
            if existing {
                try await Self.existingName(harness: harness)
            }
            let raw = try harness.directory.raw()
            try raw.execute("""
            CREATE TRIGGER refuse_name_source AFTER INSERT ON interest_source_posts
            BEGIN SELECT RAISE(ABORT, 'test'); END;
            """)
            let before = try raw.snapshot()
            let changes = await harness.store.changes()
            #expect(try await harness.engine.step() == .failed(EngineFailureTests.refusedByTrigger))
            #expect(try raw.snapshot() == before)
            try await harness.store.setLastRan(EngineFixtures.start)
            #expect(await firstChange(changes) == .lastRanChanged)
        }
    }

    @Test(arguments: [0, 1, 2])
    func `withdrawn held response cannot store extracted names`(withdrawal: Int) async throws {
        var setup = try EngineInterestExtractionTests.setup(names: [["Rust"]])
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let post = try EngineInterestExtractionTests.source(
                "Rust",
                at: EngineFixtures.time("09:40:00"),
            )
            try await EngineInterestExtractionTests.queue(post, harness: harness)
            let engine = harness.engine
            let task = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            try await Self.withdraw(withdrawal, post: post.id, harness: harness)
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let changes = await harness.store.changes()
            harness.model.releaseHeld()
            let result = try await task.value
            #expect(result == .waiting(until: EngineFixtures.start))
            #expect(try raw.snapshot() == before)
            try await harness.store.setLastRan(EngineFixtures.start)
            #expect(await firstChange(changes) == .lastRanChanged)
        }
    }

    @Test
    func `cancelled response leaves no names or scene`() async throws {
        var setup = try EngineInterestExtractionTests.setup(names: [["Rust"]])
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let post = try EngineInterestExtractionTests.source(
                "Rust",
                at: EngineFixtures.time("09:40:00"),
            )
            try await EngineInterestExtractionTests.queue(post, harness: harness)
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let engine = harness.engine
            let task = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            task.cancel()
            harness.model.releaseHeld()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(try raw.snapshot() == before)
        }
    }
}
