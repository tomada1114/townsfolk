import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// Groups, their order, quote lines, your name, and the title (REQ-001, REQ-002, REQ-006,
/// REQ-011).
@MainActor
@Suite("Timeline grouping")
struct TimelineGroupingTests {
    private let clock = ManualClock(start: Fixtures.at("13:00:00"))

    /// Each post's header name, top to bottom, as a reader sees it.
    private static func names(in model: TimelineViewModel) -> [String] {
        model.groups.flatMap(\.posts).map { post in
            switch post.author {
            case let .resident(name):
                name

            case let .you(name, marker):
                [name, marker.resolved(in: .english)].compactMap(\.self).joined(separator: " ")
            }
        }
    }

    @Test
    func `a scene is one group with its posts oldest to newest`() throws {
        let scene = SceneID()
        let snapshot = try TimelineSnapshot(entries: [
            .post(Fixtures.post(Fixtures.sora, "12:00:40", "Or ask Mika?", scene: scene)),
            .post(Fixtures.post(Fixtures.jun, "12:00:00", "Told you.", scene: scene)),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(model.outline == ["Told you. / Or ask Mika?"])
        #expect(model.groups.first?.isScene == true)
    }

    @Test
    func `each post of yours is a group of its own, with no thread line`() throws {
        let snapshot = try TimelineSnapshot(entries: [
            .post(Fixtures.yours("12:00:00", "Learning Rust today.")),
            .post(Fixtures.yours("12:01:00", "Wish me luck.")),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(model.outline == ["Wish me luck.", "Learning Rust today."])
        #expect(model.groups.map(\.isScene) == [false, false])
    }

    @Test
    func `groups and event rows run newest first by their first post or the event's start`(
    ) throws {
        let early = SceneID()
        let snapshot = try TimelineSnapshot(entries: [
            .post(Fixtures.post(Fixtures.mika, "11:00:00", "The oven made a noise.", scene: early)),
            .post(Fixtures.post(Fixtures.jun, "11:30:00", "Is that good?", scene: early)),
            .event(Fixtures.event("11:10:00", "It started raining.")),
            .post(Fixtures.yours("11:20:00", "Learning Rust today.")),
            .post(Fixtures.post(Fixtures.sora, "11:40:00", "Bread is out.")),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(model.outline == [
            "Bread is out.",
            "Learning Rust today.",
            "event: It started raining.",
            "The oven made a noise. / Is that good?",
        ])
    }

    @Test
    func `a group and an event row at the same moment put the group above`() throws {
        let snapshot = try TimelineSnapshot(entries: [
            .event(Fixtures.event("12:00:00", "You moved to Maplewood.", kind: .founding)),
            .post(Fixtures.post(Fixtures.mika, "12:00:00", "Welcome.")),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(model.outline == ["Welcome.", "event: You moved to Maplewood."])
    }

    @Test
    func `just founded, the timeline is one group above the founding row`() async throws {
        try await withFoundedStore { store, _, _ in
            let storeClock = ManualClock(start: StoreFixtures.minutes(2))
            let model = try Fixtures.model(store: store, clock: storeClock)
            try await whileRunning(model, on: storeClock) {
                #expect(model.outline == [
                    "Bread is out at the bakery. / Get there before eight.",
                    "event: You moved to Maplewood.",
                ])
                #expect(model.title == "Maplewood")
            }
        }
    }

    @Test
    func `a group whose first post replies outside it starts with a quote of that post`(
    ) throws {
        let mikas = try Fixtures.post(Fixtures.mika, "11:20:00", "The oven made a goose noise.")
        let snapshot = try TimelineSnapshot(entries: [
            .post(mikas),
            .post(Fixtures.post(Fixtures.jun, "12:00:00", "Poor oven.", replyTo: mikas.id)),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        let quote = try #require(model.groups.first?.quote)
        #expect(quote.postID == mikas.id)
        #expect(quote.name == "Mika")
        #expect(model.line(of: quote).resolved(in: .english)
            == "Mika: \"The oven made a goose noise.\"")
        #expect(model.groups.last?.quote == nil)
    }

    @Test
    func `a group starting a new topic, or replying inside itself, has no quote line`(
    ) throws {
        let scene = SceneID()
        let jun = try Fixtures.post(Fixtures.jun, "12:00:00", "Told you.", scene: scene)
        let snapshot = try TimelineSnapshot(entries: [
            .post(jun),
            .post(Fixtures.post(
                Fixtures.sora,
                "12:00:40",
                "Or ask?",
                scene: scene,
                replyTo: jun.id,
            )),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(model.groups.map(\.quote) == [nil])
    }

    @Test
    func `a reply to a post older than every loaded page quotes it from the store`(
    ) async throws {
        try await withFoundedStore { store, founding, _ in
            let mio = founding.firstScene.posts[0]
            let reply = try ResidentPostDraft(
                author: founding.residents[1].id,
                time: StoreFixtures.minutes(5),
                text: "Still thinking about that bread.",
                replyTarget: mio.id,
            ).make()
            try await store.storeScene(TownStore.SceneStep(posts: [reply]))
            let storeClock = ManualClock(start: StoreFixtures.minutes(6))
            let model = try Fixtures.model(store: store, clock: storeClock, pageSize: 1)
            try await whileRunning(model, on: storeClock) {
                #expect(model
                    .outline ==
                    ["↩ Bread is out at the bakery. | Still thinking about that bread."])
                #expect(model.groups.first?.quote?.name == "Mio")
            }
        }
    }

    @Test
    func `your posts carry your current name and (you), and a new name shows on every one`(
    ) throws {
        let first = try Fixtures.yours("12:00:00", "Learning Rust today.")
        let snapshot = try TimelineSnapshot(entries: [
            .post(first),
            .post(Fixtures.yours("12:05:00", "Still learning.")),
            .post(Fixtures.post(Fixtures.mika, "12:10:00", "Good luck!", replyTo: first.id)),
        ])
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(Self.names(in: model) == ["Mika", "Tomo (you)", "Tomo (you)"])
        #expect(model.groups.first?.quote?.name == "Tomo")

        try model.displayNameChanged(DisplayName("Hana"))
        #expect(Self.names(in: model) == ["Mika", "Hana (you)", "Hana (you)"])
        #expect(model.groups.first?.quote?.name == "Hana")
    }

    @Test
    func `with no name stored, your posts carry (you) alone`() throws {
        let snapshot = try TimelineSnapshot(entries: [
            .post(Fixtures.yours("12:00:00", "Learning Rust today.")),
        ])
        let model = Fixtures.model(snapshot, clock: clock, displayName: nil)
        #expect(Self.names(in: model) == ["(you)"])
    }

    @Test(arguments: [("Maplewood", "Maplewood"), (nil, "Townsfolk")] as [(String?, String)])
    func `the window is titled with the town's name, or Townsfolk before there is one`(
        town: String?,
        title: String,
    ) throws {
        var snapshot = TimelineSnapshot(entries: [])
        snapshot.townName = town
        let model = try Fixtures.model(snapshot, clock: clock)
        #expect(model.title == title)
    }
}
