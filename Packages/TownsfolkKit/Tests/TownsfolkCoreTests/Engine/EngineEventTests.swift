import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Events start and end (REQ-001–REQ-004, requirements §3.6): each turn draws a new event
/// with chance Δ ÷ 3 h, among the drawable kinds not ongoing, at most two ongoing, its
/// duration a whole number of hours within its kind's range; the model only writes its
/// one line. The shipped kinds are listed in `SeedTables.json`'s order — the turn in the
/// weather first (2–8 hours), then the shop opening (4–10), then the festival (4–12).
@Suite("Town engine events")
struct EngineEventTests {
    /// Mika alone, with `script` as the second turn's first draws and `outcomes` queued.
    static func town(
        _ script: [Double],
        _ outcomes: [FakeLanguageModelProvider.Outcome],
    ) throws -> EngineSetup {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = ScriptedGenerator(script)
        setup.outcomes = outcomes
        return setup
    }

    @Test
    func `a draw under the chance starts an event of an open kind for a drawn duration`(
    ) async throws {
        // 1 ongoing; 0.02 < 360 ÷ 10,800; the weather, the first of 13 open kinds; the
        // second of its 7 durations, 3 hours.
        var setup = try Self.town(
            [0.02, 0.0, ChangeFixtures.pick(1, of: 7)] + ChangeFixtures.noMove,
            [
                ChangeFixtures.description("It started raining."),
                .content(WritingFixtures.mikaSpeaks),
            ],
        )
        setup.priorEvents = try [
            ChangeFixtures.ongoing(
                "festival",
                "The harvest festival began.",
                endsAt: EngineFixtures.noon,
            ),
        ]
        try await withEngine(setup) { harness in
            let outcome = try await harness.stepAfterOpeningTurn()

            #expect(EngineFixtures.isStored(outcome))
            let started = try #require(await harness.store.ongoingEvents().last)
            #expect(started.kind == EventKindID(rawValue: "weather-turns"))
            #expect(started.description == "It started raining.")
            #expect(started.startsAt == ChangeFixtures.secondTurn)
            #expect(started.endsAt == EngineFixtures.time("13:12:00"))
            #expect(started.status == .ongoing)
            #expect(started.relatedResident == nil)
            #expect(try await harness.store.ongoingEvents().count == 2)
            #expect(harness.model.calls.count == 2)
        }
    }

    @Test
    func `the description call is told the town and the kind`() async throws {
        let setup = try Self.town(
            [0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            [ChangeFixtures.description("It started raining.")] + WritingFixtures.refusals(3),
        )
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            let call = try #require(harness.model.calls.first)
            #expect(call.prompt == """
            Town: Maplewood
            Setting: A small town by a slow river.
            Places: the bakery, the river, the station

            What starts now: a turn in the weather
            """)
            #expect(call.instructions.contains("at most 120 characters"))
            #expect(call.instructions.contains("names no person"))
        }
    }

    @Test
    func `a kind already ongoing is never drawn`() async throws {
        // The weather is ongoing, so the first open kind is the shop opening (4–10 hours).
        var setup = try Self.town(
            [0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            [ChangeFixtures.description("A bakery opened on the corner.")]
                + WritingFixtures.refusals(3),
        )
        setup.priorEvents = try [
            ChangeFixtures.ongoing(
                "weather-turns",
                "It started raining.",
                endsAt: EngineFixtures.noon,
            ),
        ]
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            let started = try #require(await harness.store.ongoingEvents().last)
            #expect(started.kind == EventKindID(rawValue: "shop-opens"))
            #expect(started.endsAt == EngineFixtures.time("14:12:00"))
        }
    }

    @Test(arguments: [(0.0, "13:12:00"), (0.999999, "15:12:00")])
    func `the duration stays within the kind's range bounded by the tuning`(
        draw: Double,
        ends: String,
    ) async throws {
        // The weather's 2–8 hours, bounded to 3–5.
        var setup = try Self.town(
            [0.0, 0.0, draw] + ChangeFixtures.noMove,
            [ChangeFixtures.description("It started raining.")] + WritingFixtures.refusals(3),
        )
        setup.tuning.events.eventDuration = .seconds(3 * 3_600) ... .seconds(5 * 3_600)
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            let started = try #require(await harness.store.ongoingEvents().first)
            #expect(started.endsAt == EngineFixtures.time(ends))
        }
    }

    @Test
    func `a draw at or above the chance starts nothing`() async throws {
        let setup = try Self.town(
            [0.034] + ChangeFixtures.noMove,
            [
                ChangeFixtures.description("It started raining."),
                .content(WritingFixtures.mikaSpeaks),
            ],
        )
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.store.ongoingEvents().isEmpty)
            #expect(harness.model.calls.count == 1)
            #expect(EngineFixtures.seed(in: harness.model.calls[0].prompt) != nil)
        }
    }

    @Test
    func `the first turn after launch draws nothing`() async throws {
        // Had the turn drawn for an event or a move, the scene's draws would have moved on
        // and its due time would not be the one EngineScheduleTests works out.
        var setup = try Self.town([], [.content(WritingFixtures.mikaSpeaks)])
        setup.generator = SplitMix64(seed: EngineSetup.seed)
        try await withEngine(setup) { harness in
            let outcome = try await harness.engine.step()

            let posts = try await harness.storedPosts()
            #expect(outcome == .sceneStored(
                posts: posts.map(\.id),
                nextDue: EngineFixtures.time("10:13:48.227"),
            ))
            #expect(harness.model.calls.count == 1)
        }
    }

    @Test
    func `while two events are ongoing the draw starts nothing`() async throws {
        var setup = try Self.town(
            [0.0] + ChangeFixtures.noMove,
            [.content(WritingFixtures.mikaSpeaks)],
        )
        setup.priorEvents = try [
            ChangeFixtures.ongoing("festival", "The festival began.", endsAt: EngineFixtures.noon),
            ChangeFixtures.ongoing("lost-pet", "A cat went missing.", endsAt: EngineFixtures.noon),
        ]
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.store.ongoingEvents().count == 2)
            #expect(harness.model.calls.count == 1)
            #expect(try await harness.storedPosts().count == 1)
        }
    }

    @Test
    func `when every kind is ongoing no event starts`() async throws {
        var setup = try Self.town(
            [0.0] + ChangeFixtures.noMove,
            [.content(WritingFixtures.mikaSpeaks)],
        )
        setup.seedTables = try ChangeFixtures.tables(kinds: ["snow", "fog"])
        setup.tuning.events.maxOngoingEvents = 3
        setup.priorEvents = try [
            ChangeFixtures.ongoing("snow", "Snow is falling.", endsAt: EngineFixtures.noon),
            ChangeFixtures.ongoing("fog", "A fog rolled in.", endsAt: EngineFixtures.noon),
        ]
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.store.ongoingEvents().count == 2)
            #expect(harness.model.calls.count == 1)
        }
    }

    @Test
    func `an event whose end has come is ended at the turn and stays in the log`() async throws {
        var setup = try Self.town([], [.content(WritingFixtures.mikaSpeaks)])
        let later = try ChangeFixtures.ongoing(
            "lost-pet",
            "A cat went missing.",
            endsAt: EngineFixtures.time("10:06:00.001"),
        )
        setup.priorEvents = try [
            ChangeFixtures.ongoing("festival", "The festival began.", endsAt: EngineFixtures.start),
            later,
        ]
        try await withEngine(setup) { harness in
            _ = try await harness.engine.step()

            #expect(try await harness.store.ongoingEvents() == [later])
            let events = try await harness.storedEvents()
            #expect(events.map(\.kind) == ["festival", "lost-pet"])
            #expect(events.map(\.status) == ["ended", "ongoing"])
        }
    }

    @Test
    func `ending comes before the draw, so an ended event frees its place`() async throws {
        var setup = try Self.town(
            [0.0, 0.0, 0.0] + ChangeFixtures.noMove,
            [ChangeFixtures.description("It started raining.")] + WritingFixtures.refusals(3),
        )
        setup.priorEvents = try [
            ChangeFixtures.ongoing(
                "festival",
                "The festival began.",
                endsAt: ChangeFixtures.secondTurn,
            ),
            ChangeFixtures.ongoing("lost-pet", "A cat went missing.", endsAt: EngineFixtures.noon),
        ]
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            let kinds = try await harness.store.ongoingEvents().map(\.kind.rawValue)
            #expect(kinds == ["lost-pet", "weather-turns"])
        }
    }
}
