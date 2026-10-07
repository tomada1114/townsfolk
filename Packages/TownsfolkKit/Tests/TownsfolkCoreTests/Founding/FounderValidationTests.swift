import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// What founding checks in the model's answers (REQ-003, REQ-007, and the boundary
/// conditions): an answer that breaks a limit, or a resident whose name repeats, is one
/// failed attempt retried with redrawn axes; a relationship to anyone but a resident
/// invented earlier is dropped.
@Suite("Founder validation")
struct FounderValidationTests {
    /// One town answer that breaks a limit, by name.
    struct BrokenTown: CustomTestStringConvertible, Sendable {
        let label: String
        let name: String
        let setting: String
        let places: [String]

        var testDescription: String {
            label
        }

        var draft: TownDraft {
            TownDraft(name: name, setting: setting, places: places)
        }
    }

    /// One resident answer that breaks a limit, by name.
    struct BrokenResident: CustomTestStringConvertible, Sendable {
        let label: String
        let name: String
        let worry: String

        var testDescription: String {
            label
        }

        var draft: NewResidentDraft {
            NewResidentDraft(name: name, worry: worry, relationships: [])
        }
    }

    private static let threePlaces = ["the bakery", "the river", "the station"]
    private static let shortSetting = "A small town by a slow river."

    static let brokenTowns = [
        BrokenTown(
            label: "a name of 31 characters",
            name: String(repeating: "n", count: 31),
            setting: shortSetting,
            places: threePlaces,
        ),
        BrokenTown(label: "a blank name", name: "   ", setting: shortSetting, places: threePlaces),
        BrokenTown(
            label: "2 places",
            name: "Maplewood",
            setting: shortSetting,
            places: ["the bakery", "the river"],
        ),
        BrokenTown(
            label: "6 places",
            name: "Maplewood",
            setting: shortSetting,
            places: ["a", "b", "c", "d", "e", "f"],
        ),
        BrokenTown(
            label: "a place of 31 characters",
            name: "Maplewood",
            setting: shortSetting,
            places: ["the bakery", "the river", String(repeating: "p", count: 31)],
        ),
        BrokenTown(
            label: "a setting of 401 characters",
            name: "Maplewood",
            setting: String(repeating: "s", count: 401),
            places: threePlaces,
        ),
    ]

    static let brokenResidents = [
        BrokenResident(
            label: "a name of 21 characters",
            name: String(repeating: "m", count: 21),
            worry: "Rain.",
        ),
        BrokenResident(label: "a blank name", name: " ", worry: "Rain."),
        BrokenResident(label: "a blank worry", name: "Mika", worry: "  "),
    ]

    /// Jun, naming a resident not yet invented, Mika in another case and spacing, and
    /// himself.
    static let junKnowingSome = NewResidentDraft(name: "Jun", worry: "Rain.", relationships: [
        .init(name: "Sora", description: "Not here yet."),
        .init(name: " mika ", description: "Buys her bread."),
        .init(name: "Jun", description: "Himself."),
    ])

    /// Sora, naming no one in town, then Jun twice.
    static let soraKnowingSome = NewResidentDraft(name: "Sora", worry: "Clay.", relationships: [
        .init(name: "Nobody", description: "A stranger."),
        .init(name: "JUN", description: "Chess partner."),
        .init(name: "Jun", description: "Said twice."),
    ])

    @Test
    func `a town exactly at every limit is founded`() async throws {
        try await withStore { store, _ in
            let name = String(repeating: "n", count: 30)
            let places = ["a", "b", "c", "d", "e"].map { String(repeating: $0, count: 30) }
            let setting = String(repeating: "s", count: 400)
            var answers = FoundingFixtures.happyPath
            answers[0] = .town(TownDraft(name: name, setting: setting, places: places))
            let fake = FoundingFixtures.fake(answers)

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            let town = try #require(try await store.town())
            #expect(town.name == name)
            #expect(town.places == places)
            #expect(town.setting == setting)
            let event = try #require(try await timeline(in: store).last)
            guard case let .event(founding) = event else {
                Issue.record("the oldest row is not the founding row")
                return
            }
            #expect(founding.description == "You moved to \(name).")
        }
    }

    @Test(arguments: brokenTowns)
    func `a town breaking a limit is one failed attempt, retried with redrawn axes`(
        broken: BrokenTown,
    ) async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake([.town(broken.draft)] + FoundingFixtures.happyPath)
            let log = ProgressLog()

            #expect(try await found(with: founder(fake, store: store), log: log) == .founded)

            #expect(log.reported == [.town, .residents, .firstScene])
            let prompts = fake.prompts
            try #require(prompts.count == 6)
            #expect(prompts[0].hasSuffix("- baker\n- librarian\n- potter"))
            #expect(prompts[1].hasSuffix("- florist\n- barber\n- nurse"))
            #expect(try await store.town()?.name == "Maplewood")
        }
    }

    @Test(arguments: brokenResidents)
    func `a resident breaking a limit is one failed attempt, retried with redrawn axes`(
        broken: BrokenResident,
    ) async throws {
        try await withStore { store, _ in
            var answers = FoundingFixtures.happyPath
            answers.insert(.resident(broken.draft), at: 1)
            let fake = FoundingFixtures.fake(answers)

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            let prompts = fake.prompts
            try #require(prompts.count == 6)
            #expect(prompts[1].contains("Occupation: baker"))
            #expect(prompts[2].contains("Occupation: florist"))
            let mika = try #require(try await store.residents().first { $0.name == "Mika" })
            #expect(mika.profile.occupation == "florist")
        }
    }

    @Test
    func `a name repeated after trimming and ignoring case is a failed attempt`() async throws {
        try await withStore { store, _ in
            var answers = FoundingFixtures.happyPath
            let repeated = NewResidentDraft(name: "  MIKA ", worry: "Rain.", relationships: [])
            answers.insert(.resident(repeated), at: 2)
            let fake = FoundingFixtures.fake(answers)

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            let prompts = fake.prompts
            try #require(prompts.count == 6)
            #expect(prompts[2].contains("Occupation: librarian"))
            #expect(prompts[3].contains("Occupation: florist"))
            let residents = try await store.residents()
            #expect(residents.map(\.name).sorted() == ["Jun", "Mika", "Sora"])
            let jun = try #require(residents.first { $0.name == "Jun" })
            #expect(jun.profile.occupation == "florist")
        }
    }

    @Test
    func `a relationship may name only a resident invented earlier; any other is dropped`(
    ) async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake([
                .town(FoundingFixtures.maplewood),
                .resident(FoundingFixtures.mika),
                .resident(Self.junKnowingSome),
                .resident(Self.soraKnowingSome),
                .scene(FoundingFixtures.welcome),
            ])

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            let residents = try await store.residents()
            let mika = try #require(residents.first { $0.name == "Mika" })
            let storedJun = try #require(residents.first { $0.name == "Jun" })
            let storedSora = try #require(residents.first { $0.name == "Sora" })
            #expect(mika.relationships.isEmpty)
            let buysBread = try Resident.Relationship(
                resident: mika.id,
                description: "Buys her bread.",
            )
            let chess = try Resident.Relationship(
                resident: storedJun.id,
                description: "Chess partner.",
            )
            #expect(storedJun.relationships == [buysBread])
            #expect(storedSora.relationships == [chess])
            #expect(fake.calls.count == 5)
        }
    }

    @Test
    func `a relationship to an earlier resident spanning two lines is a failed attempt`(
    ) async throws {
        try await withStore { store, _ in
            let broken = NewResidentDraft(
                name: "Jun",
                worry: "Rain.",
                relationships: [.init(name: "Mika", description: "Old\nfriends.")],
            )
            var answers = FoundingFixtures.happyPath
            answers.insert(.resident(broken), at: 2)
            let fake = FoundingFixtures.fake(answers)

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            #expect(fake.calls.count == 6)
            let jun = try #require(try await store.residents().first { $0.name == "Jun" })
            #expect(jun.relationships.map(\.description) == ["Buys bread from her every morning."])
        }
    }

    @Test
    func `more than three relationships is a failed attempt`() async throws {
        try await withStore { store, _ in
            let crowded = NewResidentDraft(
                name: "Sora",
                worry: "Clay.",
                relationships: (1 ... 4).map { .init(name: "Mika", description: "Friend \($0).") },
            )
            var answers = FoundingFixtures.happyPath
            answers.insert(.resident(crowded), at: 3)
            let fake = FoundingFixtures.fake(answers)

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            #expect(fake.calls.count == 6)
            let sora = try #require(try await store.residents().first { $0.name == "Sora" })
            #expect(sora.relationships.isEmpty)
        }
    }

    @Test
    func `an answer that does not decode is a failed attempt`() async throws {
        try await withStore { store, _ in
            // A resident's answer where the town's is expected.
            let wrong: [FoundingFixtures.Answer] = [.resident(FoundingFixtures.mika)]
            let fake = FoundingFixtures.fake(wrong + FoundingFixtures.happyPath)

            let outcome = try await found(with: founder(fake, store: store))

            #expect(outcome == .founded)

            #expect(fake.calls.count == 6)
        }
    }
}
