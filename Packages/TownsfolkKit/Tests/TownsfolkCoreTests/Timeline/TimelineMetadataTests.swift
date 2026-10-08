import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

@MainActor
@Suite("Timeline resident metadata")
struct TimelineMetadataTests {
    private static func checkUnchanged(
        _ model: TimelineViewModel,
        residents: [Resident],
        entries: [TimelineEntry],
    ) {
        let refreshed = model.items
        model.townRead(nil, residents: residents)
        model.entriesArrived(entries)
        #expect(model.items == refreshed)
        #expect(model.newPostCount == 0)
        #expect(model.groups.flatMap(\.posts).allSatisfy { !model.isArrivingLive($0.id) })
    }

    @Test(arguments: [false, true])
    func `refreshed metadata repairs a shown newcomer even when entries are duplicates`(
        isAway: Bool,
    ) async throws {
        try await withFoundedStore { store, founding, _ in
            let staleResidents = try await store.residents()
            let observation = await store.timelineObservation()
            let newcomer = try ResidentDraft(name: "Hana").make()
            let move = try EventDraft(kind: .moveIn, relatedResident: newcomer.id).make()
            try await store.recordMove(TownStore.MoveStep(resident: newcomer, event: move))
            let post = try ResidentPostDraft(author: newcomer.id, text: "I brought tea.").make()
            try await store.storeScene(TownStore.SceneStep(posts: [post]))
            let inserted = try await store.timelineInsertions(after: observation.cursor)
            var snapshot = TimelineSnapshot(entries: inserted.entries)
            let staleNames = staleResidents.map { ($0.id, $0.name) }
            snapshot.residentNames = Dictionary(uniqueKeysWithValues: staleNames)
            let clock = ManualClock(start: Fixtures.at("12:00:00"))
            let model = try Fixtures.model(snapshot, clock: clock)
            #expect(model.groups.flatMap(\.posts).map(\.author) == [.resident("")])
            model.scrollPositionChanged(isAtTop: !isAway)
            let rows = model.items.map(\.id)
            let scrollRequest = model.scrollToTopRequest

            try await model.townRead(founding.town, residents: store.residents())
            model.entriesArrived(inserted.entries)

            #expect(model.groups.flatMap(\.posts).map(\.author) == [.resident("Hana")])
            #expect(model.items.map(\.id) == rows)
            #expect(model.newPostCount == 0)
            #expect(model.isAtTop == !isAway)
            #expect(model.scrollToTopRequest == scrollRequest)
            #expect(!model.isArrivingLive(post.id))
            let residents = try await store.residents()
            Self.checkUnchanged(model, residents: residents, entries: inserted.entries)
        }
    }
}
