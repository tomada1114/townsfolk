import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// Posts arriving while you read older ones: held in place and counted in the pill,
/// or inserted at once at the top (REQ-007).
@MainActor
@Suite("New posts pill")
struct NewPostsPillTests {
    private let clock = ManualClock(start: Fixtures.at("12:00:00"))

    /// One post already shown and three due at 12:00:10, 12:00:20, and 12:00:30, the
    /// second of them in the shown post's scene.
    private func busyModel() throws -> TimelineViewModel {
        let scene = SceneID()
        let snapshot = try TimelineSnapshot(entries: [
            .post(Fixtures.post(Fixtures.mika, "11:00:00", "Bread is out.", scene: scene)),
            .post(Fixtures.post(Fixtures.jun, "12:00:10", "One.")),
            .post(Fixtures.post(Fixtures.sora, "12:00:20", "Two.", scene: scene)),
            .post(Fixtures.post(Fixtures.jun, "12:00:30", "Three.")),
        ])
        return try Fixtures.model(snapshot, clock: clock)
    }

    @Test
    func `at the top, arriving posts are inserted at once and the pill stays away`(
    ) async throws {
        let model = try busyModel()
        try await whileRunning(model, on: clock) {
            await clock.advanceAndWait(by: .seconds(10))
            #expect(model.postTexts == ["One.", "Bread is out."])
            #expect(model.newPostCount == 0)
            #expect(model.pillTitle == nil)
            #expect(!model.canScrollToLatest)
        }
    }

    @Test
    func `scrolled away, arriving posts leave the rows in place and are counted`(
    ) async throws {
        let model = try busyModel()
        try await whileRunning(model, on: clock) {
            model.scrollPositionChanged(isAtTop: false)
            await clock.advanceAndWait(by: .seconds(10))
            #expect(model.postTexts == ["Bread is out."])
            #expect(model.newPostCount == 1)
            #expect(model.pillTitle?.key == "timeline.newPosts")

            await clock.advanceAndWait(by: .seconds(10))
            await clock.advanceAndWait(by: .seconds(10))
            #expect(model.postTexts == ["Bread is out."])
            #expect(model.newPostCount == 3)
            #expect(model.pillTitle?.resolved(in: .english) == "3 new posts")
            #expect(model.canScrollToLatest)
        }
    }

    @Test
    func `the pill or Scroll to Latest resets the count, shows the posts, and asks to scroll`(
    ) async throws {
        let model = try busyModel()
        try await whileRunning(model, on: clock) {
            model.scrollPositionChanged(isAtTop: false)
            await clock.advanceAndWait(by: .seconds(30))
            let request = model.scrollToTopRequest

            model.scrollToLatestChosen()
            #expect(model.newPostCount == 0)
            #expect(model.pillTitle == nil)
            #expect(model.isAtTop)
            #expect(!model.canScrollToLatest)
            #expect(model.scrollToTopRequest == request + 1)
            #expect(model.outline == ["Three.", "One.", "Bread is out. / Two."])
        }
    }

    @Test
    func `scrolling back to the top by hand shows the held posts too`() async throws {
        let model = try busyModel()
        try await whileRunning(model, on: clock) {
            model.scrollPositionChanged(isAtTop: false)
            await clock.advanceAndWait(by: .seconds(10))
            let request = model.scrollToTopRequest

            model.scrollPositionChanged(isAtTop: true)
            #expect(model.newPostCount == 0)
            #expect(model.postTexts == ["One.", "Bread is out."])
            #expect(model.scrollToTopRequest == request)
        }
    }

    @Test
    func `an event arriving while away waits with the posts but is not counted`() async throws {
        let snapshot = try TimelineSnapshot(entries: [
            .post(Fixtures.post(Fixtures.mika, "11:00:00", "Bread is out.")),
            .event(Fixtures.event("12:00:10", "It started raining.")),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        try await whileRunning(model, on: clock) {
            model.scrollPositionChanged(isAtTop: false)
            await clock.advanceAndWait(by: .seconds(10))
            #expect(model.outline == ["Bread is out."])
            #expect(model.newPostCount == 0)

            model.scrollToLatestChosen()
            #expect(model.outline == ["event: It started raining.", "Bread is out."])
        }
    }

    @Test
    func `a snapshot can hold posts that arrived while away`() throws {
        var snapshot = try TimelineSnapshot(entries: [
            .post(Fixtures.post(Fixtures.mika, "11:00:00", "Bread is out.")),
        ])
        snapshot.arrivedWhileAway = try [.post(Fixtures.post(Fixtures.jun, "11:30:00", "One."))]
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(!model.isAtTop)
        #expect(model.newPostCount == 1)
        #expect(model.postTexts == ["Bread is out."])
    }
}
