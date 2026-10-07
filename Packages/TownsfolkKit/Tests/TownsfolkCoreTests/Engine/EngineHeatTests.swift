import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// No scene while the Mac is too hot (REQ-006; `docs/architecture.md` › Quality targets):
/// a serious or critical thermal state skips a due turn without a model call, and the
/// first draw of SplitMix64 seeded 42, 1.2415…, sets the next due time.
@Suite("Town engine heat")
struct EngineHeatTests {
    @Test(arguments: [ThermalState.serious, .critical])
    func `no scene while the Mac is too hot`(state: ThermalState) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.thermalState = state
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            #expect(outcome == .skipped(
                .tooHot(state),
                nextDue: EngineFixtures.time("10:13:26.963"),
            ))
            #expect(harness.model.calls.isEmpty)
            #expect(try await harness.storedPosts().isEmpty)
            #expect(try await harness.storedDue() == EngineFixtures.time("10:13:26.963"))
        }
    }

    @Test(arguments: [ThermalState.nominal, .fair])
    func `scenes run as usual while the Mac is nominal or fair`(state: ThermalState) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.thermalState = state
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
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
    func `a turn after the Mac cools down writes the scene`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.thermalState = .critical
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            _ = try await harness.engine.step()
            harness.thermal.current = .fair
            harness.clock.advance(by: .seconds(447))

            let outcome = try await harness.engine.step()

            #expect(harness.model.calls.count == 1)
            #expect(try await harness.storedPosts().count == 1)
            #expect(EngineFixtures.isStored(outcome))
        }
    }
}
