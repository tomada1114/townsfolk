import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// What events and moves change around a turn (REQ-009–REQ-011): an ongoing event is a
/// seed kind of its own; nothing is drawn while the Mac is too hot or the model is
/// unavailable; and an event, a move, and the scene of one turn are called one after
/// another.
@Suite("Town engine news")
struct EngineNewsTests {
    @Test
    func `an ongoing event is a seed kind of ordinary scenes`() async throws {
        // Mika alone and no topic: the seed kinds are her profile and the events, and
        // 0.99 picks the events.
        var setup = try EngineSetup.mikaAlone()
        setup.priorEvents = try [
            ChangeFixtures.ongoing(
                "weather-turns",
                "It started raining.",
                endsAt: EngineFixtures.noon,
            ),
        ]
        setup.generator = ScriptedGenerator([0.99, 0.0])
        setup.outcomes = WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            _ = try await harness.engine.step()

            let first = try #require(harness.model.calls.first).prompt
            #expect(EngineFixtures
                .seed(in: first) == #"Seed: the ongoing event "It started raining.""#)
            #expect(first.contains("Ongoing events:\n- It started raining."))
        }
    }

    @Test
    func `without an ongoing event no scene is seeded by one`() async throws {
        for seed: UInt64 in 0 ..< 10 {
            var setup = try EngineSetup.mikaAlone()
            setup.generator = SplitMix64(seed: seed)
            setup.outcomes = WritingFixtures.refusals(3)
            try await withEngine(setup) { harness in
                _ = try await harness.engine.step()

                let seeds = harness.model.calls.compactMap { EngineFixtures.seed(in: $0.prompt) }
                #expect(seeds.count == 3, "seed \(seed)")
                #expect(seeds.allSatisfy { !$0.contains("event") }, "seed \(seed)")
            }
        }
    }

    @Test(arguments: [ThermalState.serious, .critical])
    func `no event and no move is drawn while the Mac is too hot`(state: ThermalState) async throws {
        // The hot turn draws only its jitter, 0.5, so its due time is six minutes on; the
        // next turn then reads 0.0 for the event chance and starts the weather.
        var setup = try EngineSetup.mikaAlone()
        setup.generator = ScriptedGenerator([0.5, 0.0, 0.0, 0.0] + ChangeFixtures.noMove)
        setup.outcomes = [ChangeFixtures.description("It started raining.")]
            + WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            harness.thermal.current = state
            let hot = try await harness.stepAfterOpeningTurn()

            #expect(hot == .skipped(.tooHot(state), nextDue: EngineFixtures.time("10:18:00")))
            #expect(harness.model.calls.isEmpty)
            #expect(try await harness.storedEvents().isEmpty)

            harness.thermal.current = .nominal
            harness.clock.advance(by: ChangeFixtures.sixMinutes)
            _ = try await harness.engine.step()

            #expect(try await harness.store.ongoingEvents()
                .map(\.kind.rawValue) == ["weather-turns"])
        }
    }

    @Test
    func `no event and no move is drawn while the model is unavailable`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = ScriptedGenerator([0.0, 0.0, 0.0] + ChangeFixtures.noMove)
        setup.outcomes = [ChangeFixtures.description("It started raining.")]
            + WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            harness.model.availability = .appleIntelligenceOff
            #expect(try await harness.stepAfterOpeningTurn() == .modelUnavailable)
            #expect(harness.model.calls.isEmpty)

            harness.model.availability = .available
            harness.clock.advance(by: ChangeFixtures.sixMinutes)
            _ = try await harness.engine.step()

            #expect(try await harness.store.ongoingEvents()
                .map(\.kind.rawValue) == ["weather-turns"])
        }
    }

    @Test
    func `an event, a move, and the scene of one turn are called one after another`(
    ) async throws {
        var setup = try EngineSetup(residents: ChangeFixtures.residents(living: [
            "Mika",
            "Jun",
            "Aki",
        ]))
        setup.generator = ScriptedGenerator(
            [0.0, 0.0, 0.0] + ChangeFixtures.aMove + [0.5, 0.0, 0.0, 0.0, 0.0],
        )
        setup.outcomes = [
            ChangeFixtures.description("It started raining."),
            ChangeFixtures.newcomer("Ren"),
            .content(EngineFixtures.scene(by: "Ren", ["Hello, everyone."], tags: [])),
        ]
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let engine = harness.engine
            harness.model.availability = .modelNotReady
            _ = try await engine.step()
            harness.model.availability = .available
            harness.clock.advance(by: ChangeFixtures.sixMinutes)
            let stepping = Task { try await engine.step() }
            for _ in 0 ..< 3 {
                await harness.model.waitUntilHeld(count: 1)
                #expect(harness.model.inFlightCount == 1)
                #expect(try await engine.step() == .busy)
                harness.model.releaseHeld()
            }

            #expect(try await EngineFixtures.isStored(stepping.value))
            #expect(harness.model.calls.count == 3)
            #expect(harness.model.highestInFlight == 1)
            #expect(try await harness.store.ongoingEvents().count == 1)
            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki", "Ren"])
            let scene = try #require(harness.model.calls.last).prompt
            #expect(EngineFixtures.seed(in: scene) == #"Seed: the news "Ren moved in.""#)
            #expect(EngineFixtures.speakers(in: scene).first == "Ren")
        }
    }

    @Test
    func `a population with no room either way moves nobody`() async throws {
        var setup = try EngineSetup(residents: ChangeFixtures.residents(living: [
            "Mika",
            "Jun",
            "Aki",
        ]))
        setup.tuning.residents.population = 3 ... 3
        setup.generator = ScriptedGenerator([ChangeFixtures.noEvent] + ChangeFixtures.aMove + [0.0])
        setup.outcomes = [ChangeFixtures.newcomer("Ren")] + WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki"])
            #expect(try await harness.storedEvents().isEmpty)
        }
    }

    @Test
    func `a move interval of zero moves someone at every turn`() async throws {
        var setup = try EngineSetup(residents: ChangeFixtures.residents(living: [
            "Mika",
            "Jun",
            "Aki",
        ]))
        setup.tuning.residents.moveInterval = .zero ... .zero
        setup.generator = ScriptedGenerator([
            ChangeFixtures.noEvent,
            0.999999,
            0.5,
            0.0,
            0.0,
            0.0,
            0.0,
        ])
        setup.outcomes = [ChangeFixtures.newcomer("Ren")] + WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki", "Ren"])
        }
    }
}
