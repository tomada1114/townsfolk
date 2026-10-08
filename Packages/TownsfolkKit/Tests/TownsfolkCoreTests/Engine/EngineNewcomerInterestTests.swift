import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Newcomer name interests")
struct EngineNewcomerInterestTests {
    struct Draw: Sendable {
        let chance: Double
        let index: Int
        let term: String?
    }

    static func setup(draws: [Double]) throws -> EngineSetup {
        var setup = try EngineSetup(residents: EngineMoveTests.threeAndHana())
        setup
            .generator = ScriptedGenerator(EngineMoveTests.moveDraws(direction: 0) + EngineMoveTests
                .axes(0) + draws)
        setup.outcomes = [
            ChangeFixtures.newcomer("Ren"),
            .content(EngineFixtures.scene(by: "Ren", ["Hello."], tags: [])),
        ]
        return setup
    }

    static func names(harness: EngineHarness) async throws -> [Interest] {
        let rust = try Interest(
            id: Interest.ID(),
            term: "Rust",
            firstMentionedAt: StoreFixtures.morning,
            lastMentionedAt: StoreFixtures.minutes(2),
            mentions: 1,
        )
        let manga = try Interest(
            id: Interest.ID(),
            term: "Manga",
            firstMentionedAt: StoreFixtures.morning,
            lastMentionedAt: StoreFixtures.minutes(1),
            mentions: 1,
        )
        try await harness.store.storeScene(.init(posts: [], interests: [rust, manga]))
        return [rust, manga]
    }

    @Test(arguments: [
        Draw(chance: 0, index: 0, term: "Rust"),
        Draw(chance: 0.499, index: 1, term: "Manga"),
        Draw(chance: 0.5, index: 0, term: nil),
        Draw(chance: 0.999, index: 1, term: nil),
    ])
    func `newcomer chance and each uniform name pick`(_ draw: Draw) async throws {
        let setup = try Self.setup(draws: [draw.chance, ChangeFixtures.pick(draw.index, of: 2)])
        try await withEngine(setup) { harness in
            let names = try await Self.names(harness: harness)
            #expect(try await EngineFixtures.isStored(harness.stepAfterOpeningTurn()))
            let resident = try #require(await harness.store.residents().first { $0.name == "Ren" })
            let selected = names.first { $0.term == draw.term }
            #expect(resident.interests == selected.map { [$0.id] } ?? [])
            let prompt = try #require(harness.model.calls.first).prompt
            if let term = draw.term {
                #expect(prompt.contains("Name brought up by the user: \"\(term)\""))
                #expect(try await harness.store.interests() == names)
            } else {
                #expect(!prompt.contains("Name brought up by the user"))
            }
        }
    }

    @Test
    func `only past held names remain eligible after living holders and exclusions`() async throws {
        let setup = try Self.setup(draws: [0, 0])
        try await withEngine(setup) { harness in
            let names = try await Self.names(harness: harness)
            let pastOnly = try EngineInterestUptakeTests.name("Past only")
            try await harness.store.storeScene(.init(posts: [], interests: [pastOnly]))
            try await harness.store.excludeInterest(names[1].id)
            let mika = harness.residents[0]
            let hana = try #require(harness.residents.last)
            let raw = try harness.directory.raw()
            try raw
                .execute(
                    """
                    INSERT INTO resident_interests VALUES ('\(mika.id.rawValue)', 0, '\(names[0].id.rawValue)');
                    INSERT INTO resident_interests VALUES ('\(hana.id.rawValue)', 0, '\(pastOnly.id.rawValue)');
                    """,
                )
            _ = try await harness.stepAfterOpeningTurn()
            let newcomer = try #require(await harness.store.residents().first { $0.name == "Ren" })
            #expect(newcomer.interests == [pastOnly.id])
        }
    }

    @Test
    func `zero name chance keeps an axes-only newcomer`() async throws {
        var setup = try Self.setup(draws: [0])
        setup.tuning.residents.newcomerFromNameChance = 0
        try await withEngine(setup) { harness in
            _ = try await Self.names(harness: harness)
            _ = try await harness.stepAfterOpeningTurn()
            #expect(try await harness.store.residents().first { $0.name == "Ren" }?.interests
                .isEmpty == true)
            #expect(!harness.model.calls[0].prompt.contains("Name brought up by the user"))
        }
    }
}
