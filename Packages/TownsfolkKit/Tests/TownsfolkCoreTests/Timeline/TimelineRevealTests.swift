import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// Posts held back until their time, arriving live, and the reply announcement (REQ-004,
/// REQ-010, REQ-012).
@MainActor
@Suite("Timeline reveal")
struct TimelineRevealTests {
    /// The issue's example: Jun's post at 12:00:00 replies to Mika's 11:20 post, Sora's
    /// follows at 12:00:40, and the timeline is read at 12:00:10.
    private struct Example {
        let mikas: Post
        let juns: Post
        let soras: Post
        let snapshot: TimelineSnapshot

        init() throws {
            let scene = SceneID()
            mikas = try Fixtures.post(Fixtures.mika, "11:20:00", "The oven made a goose noise.")
            juns = try Fixtures.post(
                Fixtures.jun,
                "12:00:00",
                "Told you.",
                scene: scene,
                replyTo: mikas.id,
            )
            soras = try Fixtures.post(Fixtures.sora, "12:00:40", "Name it.", scene: scene)
            snapshot = TimelineSnapshot(entries: [.post(mikas), .post(juns), .post(soras)])
        }
    }

    @Test
    func `a post later than now is held back, then appears at the bottom of its group`(
    ) async throws {
        let example = try Example()
        let clock = ManualClock(start: Fixtures.at("12:00:10"))
        let model = try Fixtures.model(example.snapshot, clock: clock)
        try await whileRunning(model, on: clock) {
            #expect(model.outline == [
                "↩ The oven made a goose noise. | Told you.",
                "The oven made a goose noise.",
            ])
            await clock.advanceAndWait(by: .seconds(30))
            #expect(model.outline == [
                "↩ The oven made a goose noise. | Told you. / Name it.",
                "The oven made a goose noise.",
            ])
        }
    }

    @Test
    func `a revealed post arrives live, and rows loaded at launch do not`() async throws {
        let example = try Example()
        let clock = ManualClock(start: Fixtures.at("12:00:10"))
        let model = try Fixtures.model(example.snapshot, clock: clock)
        try await whileRunning(model, on: clock) {
            #expect(!model.isArrivingLive(example.juns.id))
            await clock.advanceAndWait(by: .seconds(30))
            #expect(model.isArrivingLive(example.soras.id))
            #expect(!model.isArrivingLive(example.juns.id))

            model.arrivalShown(example.soras.id)
            #expect(!model.isArrivingLive(example.soras.id))
        }
    }

    @Test
    func `a post due exactly now is shown, and one a second later is not`() throws {
        let clock = ManualClock(start: Fixtures.at("12:00:00"))
        let snapshot = try TimelineSnapshot(entries: [
            .post(Fixtures.post(Fixtures.mika, "12:00:00", "Now.")),
            .post(Fixtures.post(Fixtures.jun, "12:00:01", "Soon.")),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(model.postTexts == ["Now."])
    }

    @Test
    func `your post stored while the timeline runs arrives live at the top`() async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = try Fixtures.model(store: store, clock: clock)
            try await whileRunning(model, on: clock) {
                let yours = try YourPostDraft(time: StoreFixtures.minutes(5)).make()
                let next = clock.sleepsStarted + 1
                try await store.storeYourPost(yours)
                await clock.waitForSleep(next)
                #expect(model.postTexts.first == "Learning Rust today.")
                #expect(model.isArrivingLive(yours.id))
            }
        }
    }

    @Test
    func `a post replying to yours is announced politely by its author's name`() async throws {
        let clock = ManualClock(start: Fixtures.at("12:00:10"))
        let yours = try Fixtures.yours("11:50:00", "Poor oven.")
        let snapshot = try TimelineSnapshot(entries: [
            .post(yours),
            .post(Fixtures.post(Fixtures.mika, "12:00:20", "Gerald now.", replyTo: yours.id)),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        try await whileRunning(model, on: clock) {
            #expect(model.announcement == nil)
            await clock.advanceAndWait(by: .seconds(10))
            let announcement = try #require(model.announcement)
            #expect(announcement.text.resolved(in: .english) == "Mika replied to you")
        }
    }

    @Test
    func `a post replying to a resident is not announced`() async throws {
        let example = try Example()
        let clock = ManualClock(start: Fixtures.at("12:00:10"))
        let model = try Fixtures.model(example.snapshot, clock: clock)
        try await whileRunning(model, on: clock) {
            await clock.advanceAndWait(by: .seconds(30))
            #expect(model.announcement == nil)
        }
    }

    @Test
    func `each announcement is a new one, even when its words repeat`() async throws {
        let clock = ManualClock(start: Fixtures.at("12:00:00"))
        let yours = try Fixtures.yours("11:50:00", "Poor oven.")
        let snapshot = try TimelineSnapshot(entries: [
            .post(yours),
            .post(Fixtures.post(Fixtures.mika, "12:00:10", "Gerald now.", replyTo: yours.id)),
            .post(Fixtures.post(Fixtures.mika, "12:00:20", "Or Gus.", replyTo: yours.id)),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        try await whileRunning(model, on: clock) {
            await clock.advanceAndWait(by: .seconds(10))
            let first = try #require(model.announcement)
            await clock.advanceAndWait(by: .seconds(10))
            let second = try #require(model.announcement)
            #expect(first != second)
            #expect(second.text.resolved(in: .english) == "Mika replied to you")
        }
    }
}
