import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// What VoiceOver reads for each part of the timeline (REQ-010).
@MainActor
@Suite("Timeline readings")
struct TimelineReadingTests {
    private let clock = ManualClock(start: Fixtures.at("12:25:00"))

    @Test
    func `posts, quotes, and groups read as the guidelines spell them`() throws {
        let mikas = try Fixtures.post(Fixtures.mika, "11:20:00", "The oven made a goose noise.")
        let scene = SceneID()
        let snapshot = try TimelineSnapshot(entries: [
            .post(mikas),
            .post(Fixtures.yours("12:00:00", "Learning Rust today.")),
            .post(Fixtures.post(
                Fixtures.jun,
                "12:24:30",
                "Poor oven.",
                scene: scene,
                replyTo: mikas.id,
            )),
            .post(Fixtures.post(Fixtures.sora, "12:24:40", "Name it.", scene: scene)),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        let groups = model.groups
        try #require(groups.count == 3)

        let scenePosts = groups[0].posts
        #expect(model.reading(of: scenePosts[0]).resolved(in: .english) == "Jun, now: Poor oven.")
        #expect(model.reading(of: groups[0]).resolved(in: .english) == "Conversation, 2 posts")
        let quote = try #require(groups[0].quote)
        #expect(model.reading(of: quote).resolved(in: .english)
            == "Replying to Mika: The oven made a goose noise.")

        let yours = try #require(groups[1].posts.first)
        #expect(model.reading(of: yours).resolved(in: .english) == "You, 25m: Learning Rust today.")
    }

    @Test
    func `the Town menu reads Town, with Scroll to Latest`() {
        #expect(TimelineViewModel.townMenuTitle.resolved(in: .english) == "Town")
        #expect(TimelineViewModel.scrollToLatestTitle.resolved(in: .english) == "Scroll to Latest")
    }

    @Test
    func `each row is identified by its scene, your post, or its event`() throws {
        let scene = SceneID()
        let yours = try Fixtures.yours("12:10:00", "Learning Rust today.")
        let event = try Fixtures.event("12:05:00", "It started raining.")
        let snapshot = try TimelineSnapshot(entries: [
            .post(yours),
            .event(event),
            .post(Fixtures.post(Fixtures.mika, "12:00:00", "Bread is out.", scene: scene)),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(model.items.map(\.id) == [.yourPost(yours.id), .event(event.id), .scene(scene)])
        #expect(model.groups.map { $0.posts.map(\.isYours) } == [[true], [false]])
    }
}
