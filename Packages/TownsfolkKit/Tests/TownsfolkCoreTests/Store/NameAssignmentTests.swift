import Foundation
import Testing
import TownsfolkCore

@Suite("Atomic resident name assignments")
struct NameAssignmentTests {
    private static func prepare(race: Int, store: TownStore) async throws -> (Interest, Resident) {
        try await store.found(StoreFixtures.founding())
        let name = try EngineInterestUptakeTests.name("Rust")
        let filler = try (0 ..< 5).map { try EngineInterestUptakeTests.name("Filler \($0)") }
        try await store.storeScene(.init(posts: [], interests: [name] + filler))
        let original = try #require(await store.residents().first)
        let count = race == 3 ? 5 : 4
        let updated = try Resident(
            id: original.id,
            name: original.name,
            profile: StoreFixtures.profile(),
            movedInAt: original.movedInAt,
            status: race == 2 ? .movedOut : .living,
            movedOutAt: race == 2 ? StoreFixtures.minutes(1) : nil,
            relationships: original.relationships,
            interests: Array(filler.prefix(count)).map(\.id),
        )
        let event = try EventDraft(relatedResident: original.id).make()
        try await store.recordMove(.init(resident: updated, event: event))
        if race == 1 {
            try await store.excludeInterest(name.id)
        }
        if race == 4 {
            let other = try #require(await store.residents().last)
            let held = try Resident(
                id: other.id,
                name: other.name,
                profile: other.profile,
                movedInAt: other.movedInAt,
                interests: [name.id],
            )
            try await store.recordMove(.init(
                resident: held,
                event: EventDraft(relatedResident: other.id).make(),
            ))
        }
        return (name, updated)
    }

    @Test(arguments: [0, 1, 2, 3, 4])
    func `assignment rechecks exclusion living holder capacity and preserves the resident`(
        race: Int,
    ) async throws {
        try await withStore { store, _ in
            let (name, updated) = try await Self.prepare(race: race, store: store)
            let original = updated
            try await store.storeScene(.init(
                posts: [],
                residentInterests: [.init(resident: original.id, interest: name.id)],
            ))
            let stored = try #require(await store.residents().first { $0.id == original.id })
            #expect(stored.profile == updated.profile)
            #expect(stored.relationships == updated.relationships)
            #expect(stored.status == updated.status)
            #expect(stored.interests == updated.interests + (race == 0 ? [name.id] : []))
        }
    }

    @Test
    func `assignment insert failure rolls back posts tags due and assignment`() async throws {
        try await withStore { store, directory in
            try await store.found(StoreFixtures.founding())
            let name = try EngineInterestUptakeTests.name("Rust")
            try await store.storeScene(.init(posts: [], interests: [name]))
            let resident = try #require(await store.residents().first)
            let post = try ResidentPostDraft(author: resident.id, topicTags: ["rain"]).make()
            let raw = try directory.raw()
            try raw
                .execute(
                    """
                    CREATE TRIGGER refuse_assignment AFTER INSERT ON resident_interests
                    BEGIN SELECT RAISE(ABORT, 'test'); END;
                    """,
                )
            let before = try raw.snapshot()
            let changes = await store.changes()
            await #expect(throws: EngineFailureTests.refusedByTrigger) {
                try await store.storeScene(.init(
                    posts: [post],
                    residentInterests: [.init(resident: resident.id, interest: name.id)],
                    nextOrdinarySceneDue: EngineFixtures.noon,
                ))
            }
            #expect(try raw.snapshot() == before)
            try await store.setLastRan(EngineFixtures.start)
            #expect(await firstChange(changes) == .lastRanChanged)
        }
    }
}
