import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Residents move in and away (REQ-005–REQ-008, requirements §3.6): about one move per
/// 1–2 days of running time, a move-in with chance (10 − n) ÷ 7 among n living, each move
/// one transaction with its event. A turn's draws, after the event chance: the span d,
/// the move chance, the direction, then a move-in's four axes — occupation (33 shipped),
/// personality (21), life stage (7), hobby (31) — or the one leaving.
@Suite("Town engine moves")
struct EngineMoveTests {
    /// A move among `living` residents with the direction drawn as `draw`, and how many
    /// live afterwards.
    struct Direction: Sendable, CustomTestStringConvertible {
        let living: Int
        let draw: Double
        let after: Int

        var testDescription: String {
            "\(living) living, drawing \(draw)"
        }
    }

    /// The second turn's first draws up to the direction: no event, a move, `direction`.
    static func moveDraws(direction: Double) -> [Double] {
        [ChangeFixtures.noEvent] + ChangeFixtures.aMove + [direction]
    }

    /// The four axis draws that pick entry `index` of every axis.
    static func axes(_ index: Int) -> [Double] {
        [
            ChangeFixtures.pick(index, of: 33), ChangeFixtures.pick(index, of: 21),
            ChangeFixtures.pick(index, of: 7), ChangeFixtures.pick(index, of: 31),
        ]
    }

    /// Mika, Jun, and Aki living, and Hana, a florist, moved away.
    static func threeAndHana() throws -> [Resident] {
        let hana = try Resident(
            id: Resident.ID(),
            name: "Hana",
            profile: Resident.Profile(
                ageGroup: "fifties",
                occupation: "florist",
                hobby: "singing",
                worry: "her shop",
                personality: "warm",
            ),
            movedInAt: StoreFixtures.minutes(5),
            status: .movedOut,
            movedOutAt: StoreFixtures.minutes(6),
        )
        return try [EngineCast.mika(), EngineCast.jun(), EngineCast.aki(), hana]
    }

    @Test
    func `a newcomer repeating a past name is redrawn, and the next one moves in`() async throws {
        var setup = try EngineSetup(residents: Self.threeAndHana())
        setup
            .generator = ScriptedGenerator(Self.moveDraws(direction: 0.5) + Self.axes(0) + Self
                .axes(1))
        setup.outcomes = [
            ChangeFixtures.newcomer(" hana "),
            ChangeFixtures.newcomer("Ren"),
            .content(EngineFixtures.scene(by: "Ren", ["Hello, everyone."], tags: [])),
        ]
        try await withEngine(setup) { harness in
            let outcome = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.livingNames() == ["Mika", "Jun", "Aki", "Ren"])
            let ren = try #require(await harness.store.residents().last)
            #expect(ren.movedInAt == ChangeFixtures.secondTurn)
            #expect(ren.status == .living)
            #expect(try ren.profile == Resident.Profile(
                ageGroup: "university student",
                occupation: "florist",
                hobby: "birdwatching",
                worry: "finding a flat",
                personality: "shy",
            ))
            let row = StoredEvent(
                kind: "move-in",
                description: "Ren moved in.",
                startsAt: ChangeFixtures.secondTurn,
                endsAt: ChangeFixtures.secondTurn,
                status: "ended",
                resident: "Ren",
            )
            #expect(try await harness.storedEvents() == [row])
            let calls = harness.model.calls
            #expect(calls.count == 3)
            #expect(calls[0].prompt.contains("Occupation: baker"))
            #expect(calls[1].prompt.contains("Occupation: florist"))
            #expect(EngineFixtures.isStored(outcome))
            #expect(try await harness.storedPosts().map(\.author) == [.resident(ren.id)])
        }
    }

    @Test
    func `the newcomer's prompt lists every current and past resident to stay unlike`(
    ) async throws {
        var setup = try EngineSetup(residents: Self.threeAndHana())
        setup.generator = ScriptedGenerator(Self.moveDraws(direction: 0.5) + Self.axes(0))
        setup.outcomes = WritingFixtures.refusals(6)
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            let call = try #require(harness.model.calls.first)
            #expect(call.prompt == """
            Town: Maplewood
            Setting: A small town by a slow river.
            Places: the bakery, the river, the station

            The new resident, moving in now:
            Life stage: teenager
            Occupation: baker
            Personality: cheerful
            Hobby: gardening

            Names already taken: Mika, Jun, Aki, Hana
            Residents so far:
            - Mika: baker, cheerful.
            - Jun: librarian, shy.
            - Aki: postman, gruff.
            Past residents:
            - Hana: florist, warm.
            """)
            #expect(call.instructions
                .contains("unlike everyone listed under Residents so far and Past residents"))
        }
    }

    @Test
    func `at ten living one moves away, their posts stay, and they never speak again`(
    ) async throws {
        let names = ["Mika", "Jun", "Aki", "Ren", "Kai", "Yuki", "Nao", "Riku", "Sho", "Emi"]
        var setup = try EngineSetup(
            residents: ChangeFixtures.residents(living: names, movedOut: ["Sora", "Hana"]),
        )
        let jun = setup.residents[1]
        let junsPost = try ResidentPostDraft(
            author: jun.id,
            time: StoreFixtures.date("2026-10-01T09:30:00Z"),
        ).make()
        setup.priorPosts = [junsPost]
        setup.generator = ScriptedGenerator(
            Self.moveDraws(direction: 0.0) + [ChangeFixtures.pick(1, of: 10)],
        )
        setup.outcomes = WritingFixtures.refusals(200)
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.livingNames() == names.filter { $0 != "Jun" })
            let moved = try #require(await harness.store.residents().first { $0.id == jun.id })
            #expect(moved.status == .movedOut)
            #expect(moved.movedOutAt == ChangeFixtures.secondTurn)
            let row = StoredEvent(
                kind: "move-out",
                description: "Jun moved away.",
                startsAt: ChangeFixtures.secondTurn,
                endsAt: ChangeFixtures.secondTurn,
                status: "ended",
                resident: "Jun",
            )
            #expect(try await harness.storedEvents() == [row])
            #expect(try await harness.storedPosts().map(\.author) == [.resident(jun.id)])
            let first = try #require(harness.model.calls.first).prompt
            #expect(EngineFixtures.seed(in: first) == #"Seed: the news "Jun moved away.""#)
            #expect(first.contains("Past residents: Jun, Sora, Hana"))

            for _ in 0 ..< 12 {
                harness.clock.advance(by: .seconds(600))
                _ = try await harness.engine.step()
            }
            let speakers = harness.model.calls.flatMap { EngineFixtures.speakers(in: $0.prompt) }
            #expect(!speakers.isEmpty)
            #expect(!speakers.contains("Jun"))
        }
    }

    @Test(arguments: [
        Direction(living: 3, draw: 0.999999, after: 4),
        Direction(living: 10, draw: 0.0, after: 9),
        Direction(living: 5, draw: 0.71, after: 6),
        Direction(living: 5, draw: 0.72, after: 4),
    ])
    func `a move-in has chance (10 − n) ÷ 7, always in at 3 and out at 10`(
        _ direction: Direction,
    ) async throws {
        let names = ["Mika", "Jun", "Aki", "Ren", "Kai", "Yuki", "Nao", "Riku", "Sho", "Emi"]
        var setup = try EngineSetup(
            residents: ChangeFixtures.residents(living: Array(names.prefix(direction.living))),
        )
        setup
            .generator = ScriptedGenerator(Self.moveDraws(direction: direction.draw) + Self.axes(0))
        setup.outcomes = [ChangeFixtures.newcomer("Noa")] + WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            _ = try await harness.stepAfterOpeningTurn()

            #expect(try await harness.livingNames().count == direction.after)
        }
    }

    @Test
    func `the population stays within 3 to 10 over 1,000 turns`() async throws {
        // Each turn after the first counts 540 s, the cap at Normal, against a span of
        // 2,160 s: about every fourth turn moves someone. Without a display name no
        // scene is cast, so the only calls are newcomers'.
        var setup = try EngineSetup(
            residents: ChangeFixtures.residents(living: ["Mika", "Jun", "Aki"]),
        )
        setup.displayName = nil
        setup.tuning.residents.moveInterval = .seconds(2_160) ... .seconds(2_160)
        setup.tuning.events.maxOngoingEvents = 0
        setup.outcomes = (1 ... 1_000).map { ChangeFixtures.newcomer("Newcomer \($0)") }
        try await withEngine(setup) { harness in
            let raw = try harness.directory.raw()
            var seen: Set<Int> = []
            for _ in 0 ..< 1_000 {
                _ = try await harness.engine.step()
                let living = try raw.integer(
                    "SELECT count(*) FROM residents WHERE moved_out_at IS NULL",
                )
                #expect((3 ... 10).contains(living))
                seen.insert(living)
                harness.clock.advance(by: .seconds(600))
            }
            // The walk reached the minimum, where only a move-in is drawn, and went well
            // above it; the maximum's own turn is the 10-living case above.
            #expect(seen.contains(3))
            #expect(seen.count >= 6)
            #expect(try raw.count("residents") > 100)
            let names = try await harness.store.residents().map { $0.name.lowercased() }
            #expect(Set(names).count == names.count)
        }
    }
}
