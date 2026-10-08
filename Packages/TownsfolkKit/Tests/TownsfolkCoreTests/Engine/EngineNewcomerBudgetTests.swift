import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Newcomer context budget")
struct EngineNewcomerBudgetTests {
    private static func residents() throws -> [Resident] {
        let past = try (0 ..< 20).map { index in
            try Resident(
                id: Resident.ID(),
                name: "Past \(index)",
                profile: Resident.Profile(
                    ageGroup: "retired",
                    occupation: "old occupation \(index) " + String(repeating: "x", count: 100),
                    hobby: "singing",
                    worry: "the garden",
                    personality: "old personality \(index)",
                ),
                movedInAt: StoreFixtures.minutes(5),
                status: .movedOut,
                movedOutAt: StoreFixtures.minutes(6 + index),
            )
        }
        // Reverse input order: eviction follows departure dates, not storage order.
        return try [EngineCast.mika(), EngineCast.jun(), EngineCast.aki()] + past.reversed()
    }

    @Test
    func `large past population fits each retry without forgetting names or living profiles`(
    ) async throws {
        var setup = try EngineSetup(residents: Self.residents())
        setup.displayName = nil
        setup.contextSize = 2_924
        setup.generator = ScriptedGenerator(
            EngineMoveTests.moveDraws(direction: 0.5) + EngineMoveTests.axes(0)
                + EngineMoveTests.axes(1),
        )
        setup.outcomes = [.failure(.refused), ChangeFixtures.newcomer("Ren")]
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki", "Ren"])
            #expect(harness.model.calls.count == 2)
            for call in harness.model.calls {
                let tokens = try harness.model.tokenCount(
                    instructions: call.instructions,
                    prompt: call.prompt,
                )
                #expect(tokens <= 1_900)
                let namesLine = try #require(call.prompt.split(separator: "\n").first { line in
                    line.hasPrefix("Names already taken: ")
                })
                let names = namesLine.dropFirst("Names already taken: ".count)
                    .components(separatedBy: ", ")
                #expect(Set(names) == Set(setup.residents.map(\.name)))
                #expect(call.prompt.contains("- Mika: baker, cheerful."))
                #expect(call.prompt.contains("- Jun: librarian, shy."))
                #expect(call.prompt.contains("- Aki: postman, gruff."))
                #expect(!call.prompt.contains("old occupation 0 "))
                #expect(call.prompt.contains("old occupation 19 "))
                let retained = (0 ..< 20).filter { call.prompt.contains("old occupation \($0) ") }
                let first = try #require(retained.first)
                #expect(retained == Array(first ..< 20))
            }
            #expect(harness.model.calls[0].prompt.contains("Occupation: baker"))
            #expect(harness.model.calls[1].prompt.contains("Occupation: florist"))
        }
    }

    @Test
    func `an impossible all names prompt drops the move before generating`() async throws {
        var setup = try EngineSetup(residents: Self.residents())
        setup.displayName = nil
        setup.contextSize = 1_100
        setup.generator = ScriptedGenerator(
            EngineMoveTests.moveDraws(direction: 0.5) + EngineMoveTests.axes(0)
                + EngineMoveTests.axes(1) + EngineMoveTests.axes(2),
        )
        setup.outcomes = [ChangeFixtures.newcomer("Ren")]
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(harness.model.calls.isEmpty)
            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki"])
            #expect(try await harness.storedEvents().isEmpty)
        }
    }

    @Test
    func `cancellation during a fitted newcomer call stores nothing and propagates`() async throws {
        var setup = try EngineSetup(residents: Self.residents())
        setup.displayName = nil
        setup.contextSize = 2_924
        setup.holdsResponses = true
        setup.generator = ScriptedGenerator(
            EngineMoveTests.moveDraws(direction: 0.5) + EngineMoveTests.axes(0),
        )
        setup.outcomes = [ChangeFixtures.newcomer("Ren")]
        try await withEngine(setup) { harness in
            harness.model.availability = .modelNotReady
            _ = try await harness.engine.step()
            harness.model.availability = .available
            harness.clock.advance(by: ChangeFixtures.sixMinutes)
            let engine = harness.engine
            let stepping = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)

            stepping.cancel()

            await #expect(throws: CancellationError.self) {
                try await stepping.value
            }
            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki"])
            #expect(try await harness.storedEvents().isEmpty)
        }
    }
}
