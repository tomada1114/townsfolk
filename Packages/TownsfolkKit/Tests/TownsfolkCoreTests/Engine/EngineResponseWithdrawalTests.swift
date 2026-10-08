import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@Suite("Town response withdrawal")
struct EngineResponseWithdrawalTests {
    @Test(arguments: [0, 1, 2])
    func `withdrawn held response does not commit`(withdrawal: Int) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.holdsResponses = true
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let post = try EngineResponseFixtures.post(at: EngineFixtures.time("10:00:00"))
            try await harness.engine.submitYourPost(post, speed: .normal)
            let engine = harness.engine
            let scene = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            try await withdraw(withdrawal, post: post.id, harness: harness)
            let before = try #require(await harness.store.schedule())
            let changes = await harness.store.changes()
            harness.model.releaseHeld()
            let result = try await scene.value
            #expect(result == .waiting(until: before.nextOrdinarySceneDue))
            #expect(before.pendingResponses.count == (withdrawal == 0 ? 3 : 1))
            let after = try #require(await harness.store.schedule())
            #expect(after.nextOrdinarySceneDue == before.nextOrdinarySceneDue)
            #expect(after.pendingResponses == (withdrawal == 2 ? [] : before.pendingResponses))
            #expect(try await harness.storedPosts().allSatisfy { $0.author == .you })
            try await harness.store.setLastRan(EngineFixtures.start)
            if withdrawal == 2 {
                #expect(await firstChange(changes) == .pendingResponsesChanged)
            }
            #expect(await firstChange(changes) == .lastRanChanged)
        }
    }

    private func withdraw(_ withdrawal: Int, post: Post.ID, harness: EngineHarness) async throws {
        switch withdrawal {
        case 0:
            for second in 0 ..< 3 {
                let newer = try EngineResponseFixtures.post(
                    at: EngineFixtures.start.addingTimeInterval(Double(second)),
                )
                try await harness.engine.submitYourPost(newer, speed: .normal)
            }

        case 1:
            try await harness.store.updatePendingResponses(adding: [
                .init(post: post, dueAt: EngineFixtures.noon),
            ], droppingFor: [post])

        default:
            try await harness.store.excludePost(post)
        }
    }
}
