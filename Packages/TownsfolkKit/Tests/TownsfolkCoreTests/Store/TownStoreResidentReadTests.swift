import Foundation
import Testing
import TownsfolkCore

@Suite("TownStore resident reads")
struct TownStoreResidentReadTests {
    private static func residentID(_ lastByte: UInt8) -> Resident.ID {
        Resident.ID(rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, lastByte)))
    }

    private static func orderedFounding() throws -> (TownStore.FoundingStep, [Resident]) {
        let earlier = try ResidentDraft(
            name: "Earlier",
            id: residentID(4),
            movedInAt: StoreFixtures.minutes(-1),
        ).make()
        let zoe = try ResidentDraft(name: "zoe", id: residentID(2)).make()
        let relation = try Resident.Relationship(resident: zoe.id, description: "Neighbors.")
        let aki = try ResidentDraft(name: "Aki", id: residentID(3), relationships: [relation])
            .make()
        let later = try ResidentDraft(
            name: "Later",
            id: residentID(1),
            movedInAt: StoreFixtures.minutes(1),
        ).make()
        let seed = try StoreFixtures.founding()
        let scene = SceneID()
        let firstPost = try ResidentPostDraft(author: earlier.id, scene: scene).make()
        let secondPost = try ResidentPostDraft(
            author: aki.id,
            time: StoreFixtures.minutes(1),
            replyTarget: firstPost.id,
            scene: scene,
        ).make()
        let expected = [earlier, aki, zoe, later]
        let founding = TownStore.FoundingStep(
            town: seed.town,
            residents: [later, zoe, aki, earlier],
            foundingEvent: seed.foundingEvent,
            schedule: seed.schedule,
            firstScene: TownStore.SceneStep(posts: [firstPost, secondPost]),
        )
        return (founding, expected)
    }

    @Test
    func `residents are ordered by move-in time, then binary name, after reopening`() async throws {
        let (founding, expected) = try Self.orderedFounding()
        try await withTownDirectory { directory in
            do {
                let store = try TownStore(directory: directory.town)
                try await store.found(founding)
            }

            let reopened = try TownStore(directory: directory.town)
            #expect(try await reopened.residents() == expected)
        }
    }
}
