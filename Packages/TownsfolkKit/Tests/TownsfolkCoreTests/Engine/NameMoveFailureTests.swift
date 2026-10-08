import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Name seeded move failure")
struct NameMoveFailureTests {
    @Test(arguments: [ModelCallError.refused, .other, .unavailable])
    func `model failure never assigns a newcomer name`(_ error: ModelCallError) async throws {
        var setup = try EngineNewcomerInterestTests.setup(draws: [0, 0])
        setup.displayName = nil
        setup.tuning.generation.refusalRetriesPerTurn = 0
        setup.outcomes = [.failure(error)]
        try await withEngine(setup) { harness in
            let names = try await EngineNewcomerInterestTests.names(harness: harness)
            _ = try await harness.stepAfterOpeningTurn()
            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki"])
            #expect(try await harness.store.interests() == names)
            #expect(try await harness.storedEvents().isEmpty)
            #expect(try harness.directory.raw().count("resident_interests") == 0)
        }
    }

    @Test
    func `cancelled seeded newcomer leaves every table unchanged`() async throws {
        var setup = try EngineNewcomerInterestTests.setup(draws: [0, 0])
        setup.displayName = nil
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            _ = try await EngineNewcomerInterestTests.names(harness: harness)
            harness.model.availability = .modelNotReady
            _ = try await harness.engine.step()
            harness.model.availability = .available
            harness.clock.advance(by: ChangeFixtures.sixMinutes)
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let changes = await harness.store.changes()
            let engine = harness.engine
            let task = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            task.cancel()
            harness.model.releaseHeld()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(try raw.snapshot() == before)
            try await harness.store.setLastRan(EngineFixtures.start)
            #expect(await firstChange(changes) == .lastRanChanged)
        }
    }
}
