import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// A move that fails leaves nothing (REQ-007; `docs/architecture.md:242`): a newcomer is
/// retried with redrawn axes at most twice, a model gone mid-call drops the move at once,
/// and a move the store refuses keeps neither the resident nor its row.
@Suite("Town engine move failures")
struct EngineMoveFailureTests {
    @Test
    func `a newcomer failing three times moves nobody in and leaves nothing`() async throws {
        var setup = try EngineSetup(residents: EngineMoveTests.threeAndHana())
        setup.generator = ScriptedGenerator(
            EngineMoveTests.moveDraws(direction: 0.5) + EngineMoveTests.axes(0) + EngineMoveTests
                .axes(1) + EngineMoveTests.axes(2),
        )
        setup.outcomes = [
            .failure(.refused), .failure(.other), ChangeFixtures.newcomer("Mika"),
        ] + WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki"])
            #expect(try await harness.storedEvents().isEmpty)
            let occupations = harness.model.calls.prefix(3).map { call in
                call.prompt.split(separator: "\n").first { $0.hasPrefix("Occupation: ") }
            }
            #expect(occupations == [
                "Occupation: baker",
                "Occupation: florist",
                "Occupation: postal worker",
            ])
            #expect(harness.model.calls.count == 6)
        }
    }

    @Test
    func `a model gone during a newcomer's call drops the move without retry`() async throws {
        var setup = try EngineSetup(residents: EngineMoveTests.threeAndHana())
        setup
            .generator = ScriptedGenerator(EngineMoveTests
                .moveDraws(direction: 0.5) + EngineMoveTests.axes(0))
        setup.outcomes = [.failure(.unavailable), ChangeFixtures.newcomer("Ren")]
            + WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki"])
            #expect(try await harness.storedEvents().isEmpty)
            #expect(!harness.model.calls[1].prompt.contains("The new resident"))
        }
    }

    @Test
    func `a move whose event fails to store leaves the resident out too`() async throws {
        var setup = try EngineSetup(residents: EngineMoveTests.threeAndHana())
        setup
            .generator = ScriptedGenerator(EngineMoveTests
                .moveDraws(direction: 0.5) + EngineMoveTests.axes(0))
        setup.outcomes = [ChangeFixtures.newcomer("Ren")] + WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            let raw = try harness.directory.raw()
            try raw.execute("""
            CREATE TRIGGER refuse_moves BEFORE INSERT ON events WHEN NEW.kind = 'move-in'
            BEGIN SELECT RAISE(ABORT, 'planted by the test'); END
            """)

            _ = try await harness.stepAfterOpeningTurn()

            #expect(try raw.count("residents") == 4)
            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki"])
            #expect(try await harness.storedEvents().isEmpty)
        }
    }
}
