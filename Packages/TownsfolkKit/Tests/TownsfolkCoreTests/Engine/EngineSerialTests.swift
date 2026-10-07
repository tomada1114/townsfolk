import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// One generation at a time (REQ-008; `docs/architecture.md` › Quality targets): a step
/// arriving while another awaits the writer returns without calling it, and the fake's
/// record of overlapping calls never exceeds one.
@Suite("Town engine one at a time")
struct EngineSerialTests {
    /// Enough scenes by Mika for a run of fake minutes.
    static let manyScenes: [FakeLanguageModelProvider.Outcome] = Array(
        repeating: .content(WritingFixtures.mikaSpeaks),
        count: 40,
    )

    @Test
    func `two steps started together make one call`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.outcomes = Self.manyScenes
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let engine = harness.engine
            async let first = engine.step()
            async let second = engine.step()
            await harness.model.waitUntilHeld(count: 1)
            harness.model.releaseHeld()
            let outcomes = try await [first, second]

            #expect(outcomes.count { $0 == .busy } == 1)
            #expect(outcomes.count(where: EngineFixtures.isStored) == 1)
            #expect(harness.model.calls.count == 1)
            #expect(harness.model.highestInFlight == 1)
        }
    }

    @Test
    func `ten fake minutes of run at Fast never overlap two calls`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.speed = .fast
        setup.outcomes = Self.manyScenes
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let engine = harness.engine
            let running = Task { try await engine.run() }
            var busyAnswers = 0
            while harness.clock.elapsed < .seconds(600) {
                await harness.model.waitUntilHeld(count: 1)
                if try await engine.step() == .busy {
                    busyAnswers += 1
                }
                harness.model.releaseHeld()
                await harness.clock.waitForSleepers(count: 1)
                harness.clock.advanceToNextDeadline()
            }
            // The scene due at the ten-minute mark is in its call; cancelling drops it.
            await harness.model.waitUntilHeld(count: 1)
            running.cancel()
            await #expect(throws: CancellationError.self) {
                try await running.value
            }

            let scenes = try await harness.storedPosts().count
            #expect(scenes >= 7)
            #expect(busyAnswers == scenes)
            #expect(harness.model.calls.count == scenes + 1)
            #expect(harness.model.highestInFlight == 1)
        }
    }
}
