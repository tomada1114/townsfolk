import Foundation
import Testing
import TownsfolkCore

/// The single-purpose steps of the town written, then read back unchanged (REQ-003).
@Suite("TownStore steps")
struct TownStoreStepTests {
    // MARK: The schedule

    @Test
    func `a skipped turn moves only the next due time`() async throws {
        try await withFoundedStore { store, founding, _ in
            let changes = await store.changes()
            try await store.setNextOrdinarySceneDue(StoreFixtures.minutes(20))
            var expected = founding.schedule
            expected.nextOrdinarySceneDue = StoreFixtures.minutes(20)
            #expect(try await store.schedule() == expected)
            #expect(await firstChange(changes) == .nextOrdinarySceneDueChanged)
        }
    }

    @Test
    func `last ran is recorded`() async throws {
        try await withFoundedStore { store, founding, _ in
            let changes = await store.changes()
            try await store.setLastRan(StoreFixtures.minutes(30))
            var expected = founding.schedule
            expected.lastRanAt = StoreFixtures.minutes(30)
            #expect(try await store.schedule() == expected)
            #expect(await firstChange(changes) == .lastRanChanged)
        }
    }

    // MARK: Your post

    @Test
    func `your post is stored alone, at once`() async throws {
        try await withFoundedStore { store, founding, directory in
            let target = try #require(founding.firstScene.posts.first)
            let yours = try YourPostDraft(time: StoreFixtures.minutes(4), replyTarget: target.id)
                .make()
            let changes = await store.changes()
            try await store.storeYourPost(yours)
            #expect(try await store.post(yours.id) == yours)
            #expect(try await store.schedule() == founding.schedule)
            #expect(try directory.raw().count("pending_responses") == 0)
            #expect(await firstChange(changes) == .yourPostStored(yours.id))
        }
    }

    // MARK: Pending responses

    @Test
    func `pending responses are added, and one post's dropped as another's are added`(
    ) async throws {
        try await withFoundedStore { store, _, _ in
            let oldest = try YourPostDraft(time: StoreFixtures.minutes(2)).make()
            let newest = try YourPostDraft(time: StoreFixtures.minutes(3)).make()
            try await store.storeYourPost(oldest)
            try await store.storeYourPost(newest)
            let owedOldest = [
                Schedule.PendingResponse(post: oldest.id, dueAt: StoreFixtures.minutes(30)),
                Schedule.PendingResponse(post: oldest.id, dueAt: StoreFixtures.minutes(8)),
            ]
            let changes = await store.changes()
            try await store.updatePendingResponses(adding: owedOldest)
            #expect(try await store.schedule()?.pendingResponses == owedOldest.reversed())

            let due = StoreFixtures.minutes(7)
            let owedNewest = [Schedule.PendingResponse(post: newest.id, dueAt: due)]
            try await store.updatePendingResponses(adding: owedNewest, droppingFor: [oldest.id])
            #expect(try await store.schedule()?.pendingResponses == owedNewest)
            #expect(await firstChange(changes) == .pendingResponsesChanged)
        }
    }

    // MARK: Events

    @Test
    func `an event starts ongoing, then ends and stays in the log`() async throws {
        try await withFoundedStore { store, founding, _ in
            let rain = try EventDraft(time: StoreFixtures.minutes(10)).make()
            let changes = await store.changes()
            try await store.startEvent(rain)
            #expect(try await store.ongoingEvents() == [founding.foundingEvent, rain])

            try await store.endEvent(rain.id)
            #expect(try await store.ongoingEvents() == [founding.foundingEvent])
            let ended = try TownEvent(
                id: rain.id,
                kind: rain.kind,
                description: rain.description,
                startsAt: rain.startsAt,
                endsAt: rain.endsAt,
                status: .ended,
            )
            #expect(try await store.page(before: nil, limit: 1).entries == [.event(ended)])
            var iterator = changes.makeAsyncIterator()
            #expect(await iterator.next() == .eventStarted(rain.id))
            #expect(await iterator.next() == .eventEnded(rain.id))
        }
    }

    // MARK: Moves

    @Test
    func `a newcomer moves in with the interest they start with`() async throws {
        try await withFoundedStore { store, founding, _ in
            let speaker = try #require(founding.residents.first).id
            let comics = try InterestDraft(term: "Comics").make()
            let post = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(2)).make()
            try await store.storeScene(TownStore.SceneStep(posts: [post], interests: [comics]))
            let cousins = try Resident.Relationship(resident: speaker, description: "Cousins.")
            let newcomer = try ResidentDraft(
                name: "Sora",
                movedInAt: StoreFixtures.minutes(60),
                relationships: [cousins],
                interests: [comics.id],
            ).make()
            let moveIn = try EventDraft(
                kind: .moveIn,
                time: StoreFixtures.minutes(60),
                description: "Sora moved in.",
                relatedResident: newcomer.id,
            ).make()
            let changes = await store.changes()
            try await store.recordMove(TownStore.MoveStep(resident: newcomer, event: moveIn))

            #expect(try await store.residents().last == newcomer)
            #expect(try await store.ongoingEvents().last == moveIn)
            #expect(await firstChange(changes) == .moveRecorded(newcomer.id))
        }
    }

    @Test
    func `a resident who moves out is still remembered`() async throws {
        try await withFoundedStore { store, founding, _ in
            let leaving = try #require(founding.residents.first)
            let gone = try Resident(
                id: leaving.id,
                name: leaving.name,
                profile: leaving.profile,
                movedInAt: leaving.movedInAt,
                status: .movedOut,
                movedOutAt: StoreFixtures.minutes(600),
                relationships: leaving.relationships,
            )
            let moveOut = try EventDraft(
                kind: .moveOut,
                time: StoreFixtures.minutes(600),
                description: "Mio moved out.",
                relatedResident: leaving.id,
            ).make()
            try await store.recordMove(TownStore.MoveStep(resident: gone, event: moveOut))

            let residents = try await store.residents()
            #expect(residents.count == 3)
            #expect(residents.first { $0.id == leaving.id } == gone)
            #expect(try await store.ongoingEvents().last == moveOut)
        }
    }

    // MARK: Exclusion

    @Test
    func `excluding a post keeps it readable and can be repeated`() async throws {
        try await withFoundedStore { store, founding, _ in
            let post = try #require(founding.firstScene.posts.first)
            let changes = await store.changes()
            try await store.excludePost(post.id)
            try await store.excludePost(post.id)
            #expect(try await store.post(post.id) == post)
            var iterator = changes.makeAsyncIterator()
            #expect(await iterator.next() == .postExcluded(post.id))
            #expect(await iterator.next() == .postExcluded(post.id))
        }
    }

    @Test
    func `excluding an interest leaves it out of the interest read`() async throws {
        try await withFoundedStore { store, founding, _ in
            let speaker = try #require(founding.residents.first).id
            let rust = try InterestDraft(term: "Rust").make()
            let comics = try InterestDraft(term: "Comics").make()
            let post = try ResidentPostDraft(author: speaker, time: StoreFixtures.minutes(2)).make()
            try await store.storeScene(TownStore.SceneStep(
                posts: [post],
                interests: [rust, comics],
            ))
            let changes = await store.changes()
            try await store.excludeInterest(rust.id)
            #expect(try await store.interests() == [comics])
            #expect(await firstChange(changes) == .interestExcluded(rust.id))
        }
    }
}
