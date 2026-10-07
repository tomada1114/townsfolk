import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// While the model is unavailable the town does not run (REQ-007, requirements §3.11): no
/// call, and the schedule left as it was, so the overdue scene runs once the model is back.
@Suite("Town engine availability")
struct EngineAvailabilityTests {
    @Test(arguments: [ModelAvailability.appleIntelligenceOff, .deviceNotEligible, .modelNotReady])
    func `an unavailable model leaves the schedule as it was`(
        availability: ModelAvailability,
    ) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.availability = availability
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            #expect(outcome == .modelUnavailable)
            #expect(harness.model.calls.isEmpty)
            #expect(try await harness.storedDue() == EngineFixtures.time("10:06:00"))
        }
    }

    @Test
    func `the overdue scene runs once the model is back`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.availability = .modelNotReady
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            _ = try await harness.engine.step()
            harness.model.availability = .available

            let outcome = try await harness.engine.step()

            let posts = try await harness.storedPosts()
            #expect(posts.count == 1)
            #expect(outcome == .sceneStored(
                posts: posts.map(\.id),
                nextDue: EngineFixtures.time("10:13:48.227"),
            ))
        }
    }

    @Test
    func `a model gone mid-call leaves the schedule as it was`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.outcomes = [.failure(.unavailable)]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            #expect(outcome == .modelUnavailable)
            #expect(harness.model.calls.count == 1)
            #expect(try await harness.storedPosts().isEmpty)
            #expect(try await harness.storedDue() == EngineFixtures.time("10:06:00"))
        }
    }
}
