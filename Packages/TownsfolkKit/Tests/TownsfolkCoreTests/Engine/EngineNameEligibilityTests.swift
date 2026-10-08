import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Name uptake eligibility")
struct EngineNameEligibilityTests {
    private static func holdings(
        mode: Int,
        name: Interest,
        fillers: [Interest],
        harness: EngineHarness,
    ) throws {
        let raw = try harness.directory.raw()
        let mika = harness.residents[0]
        let sora = harness.residents[1]
        if mode == 0 {
            try raw
                .execute(
                    "INSERT INTO resident_interests VALUES ('\(mika.id.rawValue)', 0, '\(name.id.rawValue)')",
                )
        } else if mode == 1 || mode == 2 {
            for (position, filler) in fillers.enumerated() {
                try raw
                    .execute(
                        """
                        INSERT INTO resident_interests VALUES
                        ('\(mika.id.rawValue)', \(position), '\(filler.id.rawValue)')
                        """,
                    )
            }
        }
        if mode >= 2 {
            try raw
                .execute(
                    "INSERT INTO resident_interests VALUES ('\(sora.id.rawValue)', 0, '\(name.id.rawValue)')",
                )
        }
    }

    @Test(arguments: [0, 1, 2, 3])
    func `living holders and full actual speakers prevent uptake while past holders do not`(
        mode: Int,
    ) async throws {
        var setup = try EngineInterestExtractionTests.setup(names: [[]])
        try setup.residents.append(EngineCast.sora())
        setup.generator = ScriptedGenerator([0.75, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        try await withEngine(setup) { harness in
            let name = try Interest(
                id: Interest.ID(),
                term: "Rust",
                firstMentionedAt: StoreFixtures.morning,
                lastMentionedAt: StoreFixtures.minutes(2),
                mentions: 1,
            )
            let fillers = try (0 ..< 5).map { try EngineInterestUptakeTests.name("Filler \($0)") }
            try await harness.store.storeScene(.init(posts: [], interests: [name] + fillers))
            try Self.holdings(mode: mode, name: name, fillers: fillers, harness: harness)
            let mika = harness.residents[0]
            let before = try await harness.store.interests()
            #expect(try await EngineFixtures.isStored(harness.engine.step()))
            let updated = try #require(await harness.store.residents().first { $0.id == mika.id })
            #expect(updated.interests == (mode == 0 || mode == 3 ? [name.id] : fillers.map(\.id)))
            #expect(updated.profile == mika.profile)
            #expect(try await harness.store.interests() == before)
        }
    }
}
