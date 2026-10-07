import Foundation
import Testing
import TownsfolkCore

/// Your post appearing at once, at the top, in the timeline that follows the store
/// (requirements.md:224, `docs/design/ux-guidelines.md:67`).
@MainActor
@Suite("Your post arriving")
struct YourPostArrivalTests {
    /// Posts `text` from a composer over `store` at the clock's date and returns once the
    /// running timeline has taken the change in.
    private static func post(
        _ text: String,
        to store: TownStore,
        on clock: ManualClock,
    ) async {
        let composer = ComposerViewModel(store: store) { clock.date }
        composer.textChanged(to: text)
        let next = clock.sleepsStarted + 1
        await composer.returnPressed()
        await clock.waitForSleep(next)
    }

    @Test
    func `at the top, your post appears first and fades in, with no scroll asked`(
    ) async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try TimelineFixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                let request = model.scrollToTopRequest
                await Self.post("Learning Rust today.", to: store, on: clock)

                let first = try #require(model.groups.first?.posts.first)
                #expect(first.text == "Learning Rust today.")
                #expect(first.isYours)
                #expect(model.isArrivingLive(first.id))
                #expect(model.scrollToTopRequest == request)
            }
        }
    }

    @Test
    func `scrolled away, your post scrolls the timeline to the top and shows what waited`(
    ) async throws {
        try await withFoundedStore { store, founding, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try TimelineFixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                model.scrollPositionChanged(isAtTop: false)
                let resident = try ResidentPostDraft(
                    author: founding.residents[0].id,
                    time: StoreFixtures.minutes(4),
                    text: "Rain again.",
                ).make()
                let next = clock.sleepsStarted + 1
                try await store.storeScene(TownStore.SceneStep(posts: [resident]))
                await clock.waitForSleep(next)
                #expect(model.newPostCount == 1)
                let request = model.scrollToTopRequest

                await Self.post("Learning Rust today.", to: store, on: clock)
                #expect(model.isAtTop)
                #expect(model.newPostCount == 0)
                #expect(model.scrollToTopRequest == request + 1)
                #expect(Array(model.outline.prefix(2)) == ["Learning Rust today.", "Rain again."])
                let first = try #require(model.groups.first?.posts.first)
                #expect(model.isArrivingLive(first.id))
            }
        }
    }
}
