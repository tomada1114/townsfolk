import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Atomic name seeded moves")
struct NameMoveRaceTests {
    private static func prime(_ harness: EngineHarness) async throws {
        harness.model.availability = .modelNotReady
        _ = try await harness.engine.step()
        harness.model.availability = .available
        harness.clock.advance(by: ChangeFixtures.sixMinutes)
    }

    @Test(arguments: [false, true])
    func `excluded or claimed held newcomer seed retries without storing that resident`(
        claimed: Bool,
    ) async throws {
        var setup = try EngineNewcomerInterestTests.setup(draws: [0, 0])
        setup.displayName = nil
        setup.holdsResponses = true
        setup.tuning.generation.refusalRetriesPerTurn = 1
        setup.outcomes = [ChangeFixtures.newcomer("Ren"), .failure(.refused)]
        try await withEngine(setup) { harness in
            let name = try EngineInterestUptakeTests.name("Rust")
            try await harness.store.storeScene(.init(posts: [], interests: [name]))
            try await Self.prime(harness)
            let engine = harness.engine
            let task = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            if claimed {
                let mika = harness.residents[0]
                try harness.directory.raw()
                    .execute(
                        "INSERT INTO resident_interests VALUES ('\(mika.id.rawValue)', 0, '\(name.id.rawValue)')",
                    )
            } else {
                try await harness.store.excludeInterest(name.id)
            }
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let changes = await harness.store.changes()
            harness.model.releaseHeld()
            await harness.model.waitUntilHeld(count: 1)
            harness.model.releaseHeld()
            _ = try await task.value
            #expect(harness.model.calls.count == 2)
            #expect(!harness.model.calls[1].prompt.contains("Name brought up by the user"))
            // No display name skips only the ordinary due; the move must change no town content.
            var after = try raw.snapshot()
            after["schedule"] = before["schedule"]
            #expect(after == before)
            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki"])
            #expect(await firstChange(changes) == .nextOrdinarySceneDueChanged)
        }
    }

    @Test
    func `failure after newcomer interest insertion rolls back resident and move event`(
    ) async throws {
        var setup = try EngineNewcomerInterestTests.setup(draws: [0, 0])
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let name = try EngineInterestUptakeTests.name("Rust")
            try await harness.store.storeScene(.init(posts: [], interests: [name]))
            let raw = try harness.directory.raw()
            try raw.execute("""
            CREATE TRIGGER refuse_newcomer_interest AFTER INSERT ON resident_interests
            BEGIN SELECT RAISE(ABORT, 'test'); END;
            """)
            try await Self.prime(harness)
            let before = try raw.snapshot()
            let changes = await harness.store.changes()
            let engine = harness.engine
            let task = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            harness.model.releaseHeld()
            // The next ordinary scene is held before it can mutate the schedule.
            await harness.model.waitUntilHeld(count: 1)
            #expect(try raw.snapshot() == before)
            #expect(try await harness.storedEvents().isEmpty)
            try await harness.store.setLastRan(EngineFixtures.start)
            #expect(await firstChange(changes) == .lastRanChanged)
            task.cancel()
            harness.model.releaseHeld()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test
    func `budget trimming retains the seed and every uniqueness name`() async throws {
        let past = try (0 ..< 20).map { index in
            try Resident(
                id: Resident.ID(),
                name: "Past \(index)",
                profile: Resident.Profile(
                    ageGroup: "retired",
                    occupation: "old \(index) " + String(repeating: "x", count: 100),
                    hobby: "singing",
                    worry: "the garden",
                    personality: "calm",
                ),
                movedInAt: StoreFixtures.minutes(5),
                status: .movedOut,
                movedOutAt: StoreFixtures.minutes(6 + index),
            )
        }
        var setup = try EngineNewcomerInterestTests.setup(draws: [0, 0])
        setup.residents = try [EngineCast.mika(), EngineCast.jun(), EngineCast.aki()] + past
        setup.displayName = nil
        setup.contextSize = 2_924
        try await withEngine(setup) { harness in
            _ = try await EngineNewcomerInterestTests.names(harness: harness)
            _ = try await harness.stepAfterOpeningTurn()
            let call = try #require(harness.model.calls.first)
            #expect(call.prompt.contains("Name brought up by the user: \"Rust\""))
            #expect(call.prompt.contains("- Mika: baker, cheerful."))
            #expect(!call.prompt.contains("old 0 "))
            for index in 0 ..< 20 {
                #expect(call.prompt.contains("Past \(index)"))
            }
            #expect(try harness.model.tokenCount(
                instructions: call.instructions,
                prompt: call.prompt,
            ) <= 1_900)
        }
    }
}
