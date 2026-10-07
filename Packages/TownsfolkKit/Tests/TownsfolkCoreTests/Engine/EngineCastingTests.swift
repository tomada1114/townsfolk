import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Who speaks and what about (REQ-003, requirements.md:161–:163): 1–3 living residents and
/// up to 3 distinct seeds, all drawn by rules. Every turn here is refused three times, so
/// the fake records the speakers and each seed the writer was handed, in order.
@Suite("Town engine casting")
struct EngineCastingTests {
    /// One seeded turn's expected picks, worked out by hand from SplitMix64.
    struct Picks: Sendable, CustomTestStringConvertible {
        let seed: UInt64
        let speakers: [String]
        let seedLines: [String]

        var testDescription: String {
            "seed \(seed)"
        }
    }

    static let picks = [
        Picks(seed: 42, speakers: ["Jun"], seedLines: [
            #"Seed: the topic "the flood", still going."#,
            "Seed: Jun's personality: shy.",
            "Seed: Jun's worry: a leaky roof.",
        ]),
        Picks(seed: 7, speakers: ["Mika", "Aki", "Jun"], seedLines: [
            "Seed: Mika's occupation: baker.",
            "Seed: Jun's worry: a leaky roof.",
            "Seed: Mika's worry: the rent.",
        ]),
    ]

    /// Mika, Jun, Aki, and Ren living, Sora moved out; Jun's post at 09:30 is tagged
    /// "the flood" and "bread prices", and Aki's from a day before carries "old news",
    /// outside the recent window.
    static func town(seed: UInt64) throws -> EngineSetup {
        let jun = try EngineCast.jun()
        let aki = try EngineCast.aki()
        var setup = try EngineSetup(residents: [
            EngineCast.mika(), jun, aki, EngineCast.ren(), EngineCast.sora(),
        ])
        setup.priorPosts = try [
            ResidentPostDraft(
                author: aki.id,
                time: StoreFixtures.date("2026-09-30T09:00:00Z"),
                topicTags: ["old news"],
            ).make(),
            ResidentPostDraft(
                author: jun.id,
                time: StoreFixtures.date("2026-10-01T09:30:00Z"),
                topicTags: ["the flood", "bread prices"],
            ).make(),
        ]
        setup.outcomes = WritingFixtures.refusals(3)
        setup.generator = SplitMix64(seed: seed)
        return setup
    }

    /// The speakers and seed lines of one refused turn in `setup`'s town.
    static func turn(_ setup: EngineSetup) async throws -> (speakers: [String], seeds: [String]) {
        var picked: (speakers: [String], seeds: [String]) = ([], [])
        try await withEngine(setup) { harness in
            _ = try await harness.engine.step()
            let calls = harness.model.calls
            picked = (
                EngineFixtures.speakers(in: calls.first?.prompt ?? ""),
                calls.compactMap { EngineFixtures.seed(in: $0.prompt) },
            )
        }
        return picked
    }

    @Test(arguments: picks)
    func `a seeded turn picks these speakers and seeds`(_ expected: Picks) async throws {
        let picked = try await Self.turn(Self.town(seed: expected.seed))
        #expect(picked.speakers == expected.speakers)
        #expect(picked.seeds == expected.seedLines)
    }

    @Test
    func `speakers are 1 to 3 living residents, each seed's resident among them`() async throws {
        let profiles = [
            "Mika": "Seed: Mika's", "Jun": "Seed: Jun's", "Aki": "Seed: Aki's",
            "Ren": "Seed: Ren's", "Sora": "Seed: Sora's",
        ]
        for seed: UInt64 in 0 ..< 30 {
            let picked = try await Self.turn(Self.town(seed: seed))
            #expect((1 ... 3).contains(picked.speakers.count), "seed \(seed)")
            #expect(Set(picked.speakers).count == picked.speakers.count, "seed \(seed)")
            #expect(!picked.speakers.contains("Sora"), "seed \(seed)")
            #expect(Set(picked.seeds).count == picked.seeds.count, "seed \(seed)")
            #expect(picked.seeds.count == 3, "seed \(seed)")
            for line in picked.seeds where line.hasPrefix("Seed: ") && line.contains("'s ") {
                let owner = profiles.first { line.hasPrefix($0.value) }?.key
                #expect(owner.map(picked.speakers.contains) == true, "seed \(seed): \(line)")
            }
            #expect(!picked.seeds.contains { $0.contains("old news") }, "seed \(seed)")
        }
    }

    @Test
    func `with three residents every speaker count from 1 to 3 is drawn`() async throws {
        var counts: Set<Int> = []
        for seed: UInt64 in 0 ..< 30 {
            var setup = try EngineSetup(residents: [
                EngineCast.mika(), EngineCast.jun(), EngineCast.aki(), EngineCast.sora(),
            ])
            setup.outcomes = WritingFixtures.refusals(3)
            setup.generator = SplitMix64(seed: seed)
            let picked = try await Self.turn(setup)
            #expect(!picked.speakers.contains("Sora"), "seed \(seed)")
            counts.insert(picked.speakers.count)
        }
        #expect(counts == [1, 2, 3])
    }

    @Test
    func `with no topic in the recent window every seed comes from a profile`() async throws {
        for seed: UInt64 in 0 ..< 20 {
            var setup = try Self.town(seed: seed)
            setup.priorPosts.removeLast()
            let picked = try await Self.turn(setup)
            #expect(picked.seeds.count == 3, "seed \(seed)")
            #expect(picked.seeds.allSatisfy { !$0.contains("the topic") }, "seed \(seed)")
        }
    }
}
