import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// A description that fails (REQ-004): a refusal is retried with another kind, at most
/// `Tuning.generation.refusalRetriesPerTurn` (2) times; any other failure, or a line that
/// is blank, spans lines, or runs over 120 characters, starts nothing, and the turn's
/// scene still runs.
@Suite("Town engine event failures")
struct EngineEventFailureTests {
    @Test
    func `a refused description is retried with another kind, at most twice`() async throws {
        // Each refusal draws again among the kinds not yet tried: the weather, then the
        // shop opening, then the festival.
        let setup = try EngineEventTests.town(
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            WritingFixtures.refusals(3) + [.content(WritingFixtures.mikaSpeaks)],
        )
        try await withEngine(setup) { harness in
            let outcome = try await harness.stepAfterOpeningTurn()

            let kinds = harness.model.calls.prefix(3).map { call in
                call.prompt.split(separator: "\n").last.map(String.init)
            }
            #expect(kinds == [
                "What starts now: a turn in the weather",
                "What starts now: a new shop opening",
                "What starts now: a festival",
            ])
            #expect(try await harness.store.ongoingEvents().isEmpty)
            #expect(harness.model.calls.count == 4)
            #expect(EngineFixtures.isStored(outcome))
        }
    }

    @Test
    func `a description accepted after a refusal starts the kind it was written for`(
    ) async throws {
        let setup = try EngineEventTests.town(
            [0.0, 0.0, 0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            [.failure(.refused), ChangeFixtures.description("A bakery opened.")]
                + WritingFixtures.refusals(3),
        )
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            let started = try #require(await harness.store.ongoingEvents().first)
            #expect(started.kind == EventKindID(rawValue: "shop-opens"))
            #expect(started.description == "A bakery opened.")
            #expect(started.endsAt == EngineFixtures.time("14:12:00"))
        }
    }

    @Test(arguments: [
        FakeLanguageModelProvider.Outcome.failure(.other),
        .failure(.unavailable),
        .failure(.contextSizeExceeded),
        ChangeFixtures.description("   "),
        ChangeFixtures.description("It started raining.\nThen it stopped."),
        ChangeFixtures.description(String(repeating: "a", count: 121)),
        .content(WritingFixtures.mikaSpeaks),
    ])
    func `a failed call or a description out of bounds starts nothing, without retry`(
        answer: FakeLanguageModelProvider.Outcome,
    ) async throws {
        let setup = try EngineEventTests.town(
            [0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            [answer, .content(WritingFixtures.mikaSpeaks)],
        )
        try await withEngine(setup) { harness in
            let outcome = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.store.ongoingEvents().isEmpty)
            #expect(harness.model.calls.count == 2)
            #expect(EngineFixtures.isStored(outcome))
        }
    }

    @Test
    func `a description of exactly 120 characters starts the event`() async throws {
        let line = String(repeating: "a", count: 120)
        let setup = try EngineEventTests.town(
            [0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            [ChangeFixtures.description(line)] + WritingFixtures.refusals(3),
        )
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.store.ongoingEvents().map(\.description) == [line])
        }
    }

    @Test
    func `an event the store refuses leaves nothing, and the scene still runs`() async throws {
        let setup = try EngineEventTests.town(
            [0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            [
                ChangeFixtures.description("It started raining."),
                .content(WritingFixtures.mikaSpeaks),
            ],
        )
        try await withEngine(setup) { harness in
            let raw = try harness.directory.raw()
            try raw.execute("""
            CREATE TRIGGER refuse_events BEFORE INSERT ON events WHEN NEW.kind = 'weather-turns'
            BEGIN SELECT RAISE(ABORT, 'planted by the test'); END
            """)

            let outcome = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.storedEvents().isEmpty)
            #expect(EngineFixtures.isStored(outcome))
        }
    }

    @Test
    func `a step cancelled while an event is described stores nothing and throws`() async throws {
        var setup = try EngineEventTests.town(
            [0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            [ChangeFixtures.description("It started raining.")],
        )
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let engine = harness.engine
            harness.model.availability = .modelNotReady
            _ = try await engine.step()
            harness.model.availability = .available
            harness.clock.advance(by: ChangeFixtures.sixMinutes)
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let stepping = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)

            stepping.cancel()

            await #expect(throws: CancellationError.self) {
                try await stepping.value
            }
            #expect(try raw.snapshot() == before)
        }
    }
}
