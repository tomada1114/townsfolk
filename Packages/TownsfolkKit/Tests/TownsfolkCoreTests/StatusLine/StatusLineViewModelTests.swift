import Foundation
import Testing
import TownsfolkCore

/// The line chosen from the ongoing events and the recent topic tags (requirements §3.3).
@Suite("Status line content")
struct StatusLineContentTests {
    private static let rainKind = EventKindID(rawValue: "rain")
    private static let fairKind = EventKindID(rawValue: "fair")

    private static func event(
        _ kind: EventKindID,
        _ text: String,
        from start: Int,
        to end: Int,
    ) throws -> TownEvent {
        try TownEvent(
            id: TownEvent.ID(),
            kind: kind,
            description: text,
            startsAt: StoreFixtures.minutes(start),
            endsAt: StoreFixtures.minutes(end),
        )
    }

    private static func content(
        _ events: [TownEvent],
        tags: [String],
        at minute: Int,
    ) -> StatusLineContent {
        StatusLineContent(
            townName: "Maplewood",
            ongoingEvents: events,
            recentTopicTags: tags,
            now: StoreFixtures.minutes(minute),
        )
    }

    @Test
    func `an ongoing event leads, then the latest topic`() throws {
        let rain = try Self.event(Self.rainKind, "Rain since noon", from: 0, to: 180)
        let content = Self.content([rain], tags: ["the bakery's new bread", "fish"], at: 70)
        #expect(content.line == .eventAndTopic(
            event: "Rain since noon",
            topic: "the bakery's new bread",
        ))
        #expect(content.eventKind == Self.rainKind)
    }

    @Test
    func `an event alone is the event only`() throws {
        let rain = try Self.event(Self.rainKind, "Rain since noon", from: 0, to: 180)
        let content = Self.content([rain], tags: [], at: 70)
        #expect(content.line == .event("Rain since noon"))
    }

    @Test
    func `a topic alone is the topic only, with no symbol`() {
        let content = Self.content([], tags: ["fish"], at: 70)
        #expect(content.line == .topic("fish"))
        #expect(content.eventKind == nil)
    }

    @Test
    func `with nothing to say the line is the quiet day`() {
        #expect(Self.content([], tags: [], at: 70).line == .quiet(town: "Maplewood"))
    }

    @Test
    func `with two ongoing events the one that started later is shown`() throws {
        let later = try Self.event(Self.fairKind, "The fair opened", from: 30, to: 300)
        let earlier = try Self.event(Self.rainKind, "Rain since noon", from: 0, to: 180)
        let content = Self.content([later, earlier], tags: [], at: 70)
        #expect(content.line == .event("The fair opened"))
        #expect(content.eventKind == Self.fairKind)
    }

    @Test
    func `an event whose end has come falls back to the other`() throws {
        let later = try Self.event(Self.fairKind, "The fair opened", from: 30, to: 60)
        let earlier = try Self.event(Self.rainKind, "Rain since noon", from: 0, to: 180)
        #expect(Self.content([later, earlier], tags: [], at: 60).line == .event("Rain since noon"))
        #expect(Self.content([later, earlier], tags: ["fish"], at: 180).line == .topic("fish"))
    }

    @Test
    func `an event not started yet is not shown`() throws {
        let fair = try Self.event(Self.fairKind, "The fair opened", from: 90, to: 300)
        #expect(Self.content([fair], tags: [], at: 70).line == .quiet(town: "Maplewood"))
    }
}

/// The status line's view model reading the store and following it and the clock.
@MainActor
@Suite("Status line following the store")
struct StatusLineViewModelTests {
    private static let symbols: [EventKindID: String] = [
        .founding: "house",
        EventKindID(rawValue: "rain"): "cloud.rain",
    ]

    private static func model(store: TownStore, clock: ManualClock) -> StatusLineViewModel {
        StatusLineViewModel(
            store: store,
            eventSymbols: symbols,
            environment: TimelineFixtures.environment(clock: clock, pageSize: 1),
        )
    }

    private static func running(
        _ model: StatusLineViewModel,
        on clock: ManualClock,
        _ body: () async throws -> Void,
    ) async throws {
        let task = Task { await model.run() }
        defer { task.cancel() }
        await clock.waitForSleep(1)
        try await body()
    }

    private static func commit(
        on clock: ManualClock,
        _ step: () async throws -> Void,
    ) async throws {
        let next = clock.sleepsStarted + 1
        try await step()
        await clock.waitForSleep(next)
    }

    @Test
    func `before founding there is no line`() async throws {
        try await withStore { store, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = Self.model(store: store, clock: clock)
            try await Self.running(model, on: clock) {
                #expect(model.content == nil)
                #expect(model.text == nil)
                #expect(model.symbol == nil)
            }
        }
    }

    @Test
    func `just founded the move leads with the first scene's topic and its symbol`() async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = Self.model(store: store, clock: clock)
            try await Self.running(model, on: clock) {
                #expect(model.content?.line == .eventAndTopic(
                    event: "You moved to Maplewood.",
                    topic: "bakery",
                ))
                #expect(model.symbol == "house")
                #expect(model.text
                    .map { String(localized: $0) } == "You moved to Maplewood. · bakery")
            }
        }
    }

    @Test
    func `the line changes when an event starts and again when it ends`() async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = Self.model(store: store, clock: clock)
            try await Self.running(model, on: clock) {
                let rain = try EventDraft(
                    time: StoreFixtures.minutes(4),
                    description: "Rain since noon",
                )
                .make()
                try await Self.commit(on: clock) { try await store.startEvent(rain) }
                #expect(model.content?.line == .eventAndTopic(
                    event: "Rain since noon",
                    topic: "bakery",
                ))
                #expect(model.symbol == "cloud.rain")
                try await Self.commit(on: clock) { try await store.endEvent(rain.id) }
                #expect(model.content?.line == .eventAndTopic(
                    event: "You moved to Maplewood.",
                    topic: "bakery",
                ))
                #expect(model.symbol == "house")
            }
        }
    }

    @Test
    func `a scene bringing a new latest tag changes the topic`() async throws {
        try await withFoundedStore { store, founding, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = Self.model(store: store, clock: clock)
            try await Self.running(model, on: clock) {
                let post = try ResidentPostDraft(
                    author: founding.residents[0].id,
                    time: StoreFixtures.minutes(5),
                    topicTags: ["the river"],
                ).make()
                try await Self.commit(on: clock) {
                    try await store.storeScene(TownStore.SceneStep(posts: [post]))
                }
                #expect(model.content?.line == .eventAndTopic(
                    event: "You moved to Maplewood.",
                    topic: "the river",
                ))
            }
        }
    }

    @Test
    func `the clock passing the event's end falls back to the topic`() async throws {
        try await withFoundedStore { store, _, _ in
            // The founding event lasts an hour from 09:00; 30 seconds before it ends.
            let clock = ManualClock(start: StoreFixtures.minutes(60).addingTimeInterval(-30))
            let model = Self.model(store: store, clock: clock)
            try await Self.running(model, on: clock) {
                #expect(model.content?.line == .eventAndTopic(
                    event: "You moved to Maplewood.",
                    topic: "bakery",
                ))
                await clock.advanceAndWait(by: .seconds(30))
                #expect(model.content?.line == .topic("bakery"))
                #expect(model.symbol == nil)
                #expect(model.text
                    .map { String(localized: $0) } == "Everyone's talking about bakery")
            }
        }
    }

    @Test
    func `a scene repeating the latest tag leaves the line as it was`() async throws {
        try await withFoundedStore { store, founding, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = Self.model(store: store, clock: clock)
            try await Self.running(model, on: clock) {
                let before = model.content
                let post = try ResidentPostDraft(
                    author: founding.residents[1].id,
                    time: StoreFixtures.minutes(5),
                    topicTags: ["bakery"],
                ).make()
                try await Self.commit(on: clock) {
                    try await store.storeScene(TownStore.SceneStep(posts: [post]))
                }
                #expect(model.content == before)
            }
        }
    }

    @Test
    func `moving away clears the line`() async throws {
        try await withFoundedStore { store, _, _ in
            let clock = ManualClock(start: StoreFixtures.minutes(5))
            let model = Self.model(store: store, clock: clock)
            let task = Task { await model.run() }
            defer { task.cancel() }
            await clock.waitForSleep(1)
            #expect(model.content != nil)
            try await store.deleteEverything()
            while model.content != nil {
                await Task.yield()
            }
            #expect(model.text == nil)
        }
    }

    @Test
    func `the quiet day and the event-only line read in English`() {
        let quiet = StatusLineViewModel(
            content: StatusLineContent(
                townName: "Maplewood",
                ongoingEvents: [],
                recentTopicTags: [],
                now: .now,
            ),
            eventSymbols: [:],
            environment: TimelineEnvironment(locale: Locale(identifier: "en_US_POSIX")),
        )
        #expect(quiet.text.map { String(localized: $0) } == "A quiet day in Maplewood")
        #expect(String(localized: StatusLineViewModel.accessibilityLabel) == "Town status")
    }
}
