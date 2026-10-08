import Foundation
import Testing
import TownsfolkCore

/// Response retries still satisfy relationship casting after a forced reply lead.
@Suite("Town response relationships")
struct EngineResponseRelationshipTests {
    enum Partner: CaseIterable {
        case displaced
        case movedOut
        case surviving
    }

    private static func linked(_ resident: Resident, to partner: Resident) throws -> Resident {
        try Resident(
            id: resident.id,
            name: resident.name,
            profile: resident.profile,
            movedInAt: resident.movedInAt,
            relationships: [.init(resident: partner.id, description: "They play chess together.")],
        )
    }

    private static func target(by resident: Resident) throws -> Post {
        try ResidentPostDraft(author: resident.id, time: EngineFixtures.time("10:00:00")).make()
    }

    private static func partner(_ kind: Partner, displaced: Resident) throws -> Resident {
        switch kind {
        case .displaced:
            displaced

        case .movedOut:
            try EngineCast.sora()

        case .surviving:
            try EngineCast.aki()
        }
    }

    @Test(arguments: Partner.allCases)
    func `relationship retry requires its living partner after forced lead casting`(
        partnerKind: Partner,
    ) async throws {
        let mika = try EngineCast.mika()
        let ren = try EngineCast.ren()
        let partner = try Self.partner(partnerKind, displaced: mika)
        let jun = try Self.linked(EngineCast.jun(), to: partner)
        var residents = [mika, jun, ren]
        if partnerKind != .displaced {
            residents.append(partner)
        }
        var setup = EngineSetup(residents: residents)
        // Schedule two draws; cast Mika first, Jun next, and Aki when the partner survives.
        // The second ordinary seed is Jun's relationship. Ren then replaces Mika as lead.
        var draws: [Double] = [0, 0, 0, 0, partnerKind == .surviving ? 0.8 : 0.4, 0]
        if partnerKind == .surviving {
            draws.append(0)
        }
        draws += [0, partnerKind == .surviving ? 0.63 : 0.99, 0, 0, 0]
        draws += [0, 0, 0, 0]
        setup.generator = ScriptedGenerator(draws)
        let target = try Self.target(by: ren)
        setup.priorPosts = [target]
        setup.outcomes = WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            try await harness.store.storeYourPost(EngineResponseFixtures.post(
                at: EngineFixtures.time("10:00:01"),
                reply: target.id,
            ))
            _ = try await harness.engine.step()
            let calls = harness.model.calls
            #expect(calls.count == 3)
            let speakers = partnerKind == .surviving ? ["Ren", "Jun", "Aki"] : ["Ren", "Jun"]
            for call in calls {
                #expect(EngineFixtures.speakers(in: call.prompt) == speakers)
            }
            let seeds = calls.compactMap { EngineFixtures.seed(in: $0.prompt) }
            let relationship = "Seed: Jun's relationship with \(partner.name): They play chess together."
            if partnerKind == .displaced {
                #expect(!seeds.contains(relationship))
                #expect(Array(seeds.dropFirst()) == [
                    "Seed: Ren's hobby: drawing.",
                    "Seed: Ren's occupation: student.",
                ])
            } else {
                #expect(seeds.dropFirst().first == relationship)
            }
            #expect(seeds.first?.contains("Ren writes the first post.") == true)
            #expect(Set(seeds).count == 3)
        }
    }

    @Test
    func `response refill draws an eligible relationship once despite repeated stored links`(
    ) async throws {
        let jun = try EngineCast.jun()
        let originalRen = try EngineCast.ren()
        let link = try Resident.Relationship(
            resident: jun.id,
            description: "They play chess together.",
        )
        let ren = try Resident(
            id: originalRen.id,
            name: originalRen.name,
            profile: originalRen.profile,
            movedInAt: originalRen.movedInAt,
            relationships: [link, link, link],
        )
        var setup = try EngineSetup(residents: [EngineCast.mika(), jun, ren])
        // Two scheduling draws, eight ordinary casting draws, forced lead, then refill.
        // The first two ordinary seeds belong to displaced Mika. The refill's fifth
        // profile candidate is Ren's sole relationship candidate, despite repeated links.
        setup.generator = ScriptedGenerator([0, 0, 0, 0, 0.4, 0, 0, 0, 0, 0, 0, 0, 0.5, 0, 0])
        let target = try Self.target(by: ren)
        setup.priorPosts = [target]
        setup.outcomes = WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            try await harness.store.storeYourPost(EngineResponseFixtures.post(
                at: EngineFixtures.time("10:00:01"),
                reply: target.id,
            ))
            _ = try await harness.engine.step()
            let calls = harness.model.calls
            #expect(calls.count == 3)
            for call in calls {
                #expect(EngineFixtures.speakers(in: call.prompt) == ["Ren", "Jun"])
            }
            let seeds = calls.compactMap { EngineFixtures.seed(in: $0.prompt) }
            #expect(Array(seeds.dropFirst()) == [
                "Seed: Ren's relationship with Jun: They play chess together.",
                "Seed: Ren's hobby: drawing.",
            ])
            #expect(Set(seeds).count == 3)
        }
    }

    @Test
    func `forced response lead refills with a name and an eligible relationship`() async throws {
        let jun = try EngineCast.jun()
        let ren = try Self.linked(EngineCast.ren(), to: jun)
        var setup = try EngineSetup(residents: [EngineCast.mika(), jun, ren])
        // Schedule, then cast Mika and Jun with Mika's first two profile seeds.
        // Ren displaces Mika as reply lead; refill selects the name pool, then Ren's link.
        setup.generator = ScriptedGenerator([
            0, 0, 0, 0, 0.4, 0, 0, 0, 0, 0, 0, 0.75, 0, 0, 0.5,
        ])
        let target = try Self.target(by: ren)
        setup.priorPosts = [target]
        setup.outcomes = WritingFixtures.refusals(3)
        try await withEngine(setup) { harness in
            let name = try EngineInterestUptakeTests.name("Rust")
            try await harness.store.storeScene(.init(posts: [], interests: [name]))
            try await harness.store.storeYourPost(EngineResponseFixtures.post(
                at: EngineFixtures.time("10:00:01"),
                reply: target.id,
            ))
            _ = try await harness.engine.step()
            let calls = harness.model.calls
            #expect(calls.count == 3)
            for call in calls {
                #expect(EngineFixtures.speakers(in: call.prompt) == ["Ren", "Jun"])
            }
            let seeds = calls.compactMap { EngineFixtures.seed(in: $0.prompt) }
            #expect(seeds.first?.contains("Ren writes the first post.") == true)
            #expect(Array(seeds.dropFirst()) == [
                "Seed: Rust, a name Tomo brought up.",
                "Seed: Ren's relationship with Jun: They play chess together.",
            ])
            #expect(Set(seeds).count == 3)
            #expect(!seeds.contains { $0.contains("Mika's") })
        }
    }
}
