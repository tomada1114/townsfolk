import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Founding that succeeds (REQ-001, REQ-005, REQ-006): the town, its residents, the
/// founding row, the first scene, and the schedule, all stored in one transaction, with
/// progress after each step.
@Suite("Founder")
struct FounderTests {
    private static let second: TimeInterval = 1

    @Test
    func `founding reports each step in order and commits one transaction`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let log = ProgressLog()
            let changes = await store.changes()

            let outcome = try await found(with: founder(fake, store: store), log: log)

            #expect(outcome == .founded)
            #expect(log.reported == [.town, .residents, .firstScene])
            #expect(fake.calls.count == 5)
            #expect(await firstChange(changes) == .founded)
        }
    }

    @Test
    func `the town is stored as the model invented it, founded now`() async throws {
        try await withFoundedTown { store in
            let town = try #require(try await store.town())
            #expect(town.name == "Maplewood")
            #expect(town.setting == "A small town by a slow river. Mornings smell of bread.")
            #expect(town.places == ["the bakery", "the river", "the station"])
            #expect(town.foundedAt == FoundingFixtures.now)
        }
    }

    @Test
    func `each resident is stored with the drawn axes and the model's name and worry`(
    ) async throws {
        try await withFoundedTown { store in
            let residents = try await residentsByName(in: store)
            #expect(residents.keys.sorted() == ["Jun", "Mika", "Sora"])
            #expect(residents["Mika"]?.profile == Resident.Profile.expected(
                "baker",
                worry: "the oven cooling too early",
            ))
            #expect(residents["Jun"]?.profile == Resident.Profile.expected(
                "librarian",
                worry: "the leaky library roof",
            ))
            #expect(residents["Sora"]?.profile == Resident.Profile.expected(
                "potter",
                worry: "the price of clay",
            ))
        }
    }

    @Test
    func `the residents live here from the founding, knowing whom the model said`() async throws {
        try await withFoundedTown { store in
            let residents = try await residentsByName(in: store)
            let mika = try #require(residents["Mika"])
            let buysBread = try Resident.Relationship(
                resident: mika.id,
                description: "Buys bread from her every morning.",
            )
            #expect(residents["Jun"]?.relationships == [buysBread])
            #expect(mika.relationships.isEmpty)
            #expect(residents["Sora"]?.relationships.isEmpty == true)
            for resident in residents.values {
                #expect(resident.status == .living)
                #expect(resident.movedInAt == FoundingFixtures.now)
                #expect(resident.movedOutAt == nil)
                #expect(resident.interests.isEmpty)
            }
        }
    }

    @Test
    func `the founding row is the timeline's first, of the fixed founding kind`() async throws {
        try await withFoundedTown { store in
            let entries = try await timeline(in: store)
            try #require(entries.count == 3)
            guard case let .event(event) = entries[2] else {
                Issue.record("the oldest row is not an event: \(entries[2])")
                return
            }
            #expect(event.kind == .founding)
            #expect(event.description == "You moved to Maplewood.")
            #expect(event.startsAt == FoundingFixtures.now)
            #expect(event.endsAt == FoundingFixtures.now)
            #expect(event.status == .ended)
            #expect(event.relatedResident == nil)
        }
    }

    @Test
    func `the first scene's posts follow the founding row a second apart`() async throws {
        try await withFoundedTown { store in
            let mika = try #require(try await residentsByName(in: store)["Mika"])
            let posts = try await storedPosts(in: store)
            try #require(posts.count == 2)
            let (reply, first) = (posts[0], posts[1])
            #expect(first.author == .resident(mika.id))
            #expect(first.text == "Fresh loaves are out.")
            #expect(first.happenedAt == FoundingFixtures.now.addingTimeInterval(Self.second))
            #expect(first.replyTarget == nil)
            #expect(reply.author == .resident(mika.id))
            #expect(reply.text == "Come early tomorrow.")
            #expect(reply.happenedAt == FoundingFixtures.now.addingTimeInterval(2 * Self.second))
            #expect(reply.replyTarget == first.id)
            #expect(posts.map(\.origin) == [.ordinary, .ordinary])
            #expect(first.sceneID != nil)
            #expect(reply.sceneID == first.sceneID)
        }
    }

    @Test
    func `the schedule starts with nothing pending, due at the founding`() async throws {
        try await withFoundedTown { store in
            let schedule = try #require(try await store.schedule())
            #expect(schedule.nextOrdinarySceneDue == FoundingFixtures.now)
            #expect(schedule.lastRanAt == FoundingFixtures.now)
            #expect(schedule.pendingResponses.isEmpty)
        }
    }

    @Test
    func `a scene's topic tags are kept on each of its posts`() async throws {
        try await withStore { store, _ in
            let scene = WritingFixtures.content(FoundingFixtures.welcome, tags: ["bread"])
            var outcomes = FoundingFixtures.outcomes(Array(FoundingFixtures.happyPath.prefix(4)))
            outcomes.append(.content(scene))
            let founder = try founder(WritingFixtures.fake(outcomes), store: store)

            #expect(try await found(with: founder) == .founded)

            #expect(try await storedPosts(in: store).map(\.topicTags) == [["bread"], ["bread"]])
        }
    }

    @Test(arguments: [UInt64(11), 12, 13, 14])
    func `no two residents are drawn the same combination of axes`(seed: UInt64) async throws {
        try await withStore { store, _ in
            // Three combinations in all: one entry on every axis but the occupation.
            let tables = try FoundingFixtures.tables(
                occupations: ["baker", "librarian", "potter"],
                personalities: ["cheerful"],
                lifeStages: ["young adult"],
                hobbies: ["fishing"],
            )
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let generator = FoundingFixtures.SplitMix(seed: seed)

            _ = try await found(with: founder(
                fake,
                store: store,
                generator: generator,
                tables: tables,
            ))

            let prompts = fake.prompts
            try #require(prompts.count >= 4)
            let occupations = prompts[1 ... 3].flatMap { prompt in
                prompt.split(separator: "\n").filter { $0.hasPrefix("Occupation: ") }
            }
            #expect(occupations.sorted() == [
                "Occupation: baker",
                "Occupation: librarian",
                "Occupation: potter",
            ])
        }
    }
}

/// Founds ``FoundingFixtures/happyPath`` as Tomo into a fresh store, requires it to
/// succeed, and runs `body` on the store it left.
private func withFoundedTown(_ body: (TownStore) async throws -> Void) async throws {
    try await withStore { store, _ in
        let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
        let outcome = try await found(with: founder(fake, store: store))
        try #require(outcome == .founded)
        try await body(store)
    }
}

/// The stored residents, by name.
private func residentsByName(in store: TownStore) async throws -> [String: Resident] {
    let residents = try await store.residents()
    return Dictionary(uniqueKeysWithValues: residents.map { ($0.name, $0) })
}

/// The stored posts, newest first.
private func storedPosts(in store: TownStore) async throws -> [Post] {
    try await timeline(in: store).compactMap { entry in
        if case let .post(post) = entry {
            return post
        }
        return nil
    }
}

extension Resident.Profile {
    /// The profile the first-choice generator draws for `occupation`: a cheerful young
    /// adult who fishes, with the worry the model wrote.
    static func expected(_ occupation: String, worry: String) -> Self {
        do {
            return try Self(
                ageGroup: "young adult",
                occupation: occupation,
                hobby: "fishing",
                worry: worry,
                personality: "cheerful",
            )
        } catch {
            preconditionFailure("an expected profile is valid: \(error)")
        }
    }
}
