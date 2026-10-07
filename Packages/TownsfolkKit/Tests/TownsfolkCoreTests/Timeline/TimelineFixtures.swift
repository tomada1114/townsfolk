import Foundation
import TownsfolkCore

/// Residents, posts, events, and a timeline built over them, so a timeline test states
/// only what it is about.
enum TimelineFixtures {
    static let mika = Resident.ID()
    static let jun = Resident.ID()
    static let sora = Resident.ID()
    static let names = [mika: "Mika", jun: "Jun", sora: "Sora"]
    /// The kind an event row has unless a test names another.
    static let weather = EventKindID(rawValue: "weather-turns")

    /// The kinds a test's event rows may carry, each with its symbol.
    static let symbols: [EventKindID: String] = [
        .moveIn: "house",
        .moveOut: "figure.walk",
        .founding: "house",
        weather: "cloud.sun.rain",
    ]

    private static let anHour: TimeInterval = 3_600
    private static let pageSize = 100

    /// `hms` ("12:00:40") on 2026-10-01, UTC.
    static func at(_ hms: String) -> Date {
        StoreFixtures.date("2026-10-01T\(hms)Z")
    }

    /// A resident's post in a scene of its own.
    static func post(_ author: Resident.ID, _ hms: String, _ text: String) throws -> Post {
        try post(author, hms, text, scene: SceneID(), replyTo: nil)
    }

    /// A resident's post in `scene`.
    static func post(
        _ author: Resident.ID,
        _ hms: String,
        _ text: String,
        scene: SceneID,
    ) throws -> Post {
        try post(author, hms, text, scene: scene, replyTo: nil)
    }

    /// A resident's post in a scene of its own, replying to `target`.
    static func post(
        _ author: Resident.ID,
        _ hms: String,
        _ text: String,
        replyTo target: Post.ID,
    ) throws -> Post {
        try post(author, hms, text, scene: SceneID(), replyTo: target)
    }

    /// A resident's post in `scene`, replying to `target` if one is given.
    static func post(
        _ author: Resident.ID,
        _ hms: String,
        _ text: String,
        scene: SceneID,
        replyTo target: Post.ID?,
    ) throws -> Post {
        try Post(
            id: Post.ID(),
            author: .resident(author),
            text: text,
            happenedAt: at(hms),
            replyTarget: target,
            origin: .ordinary,
            sceneID: scene,
        )
    }

    /// A post of yours.
    static func yours(_ hms: String, _ text: String) throws -> Post {
        try Post(id: Post.ID(), author: .you, text: text, happenedAt: at(hms))
    }

    /// A post of yours replying to `target`.
    static func yours(_ hms: String, _ text: String, replyTo target: Post.ID) throws -> Post {
        try Post(id: Post.ID(), author: .you, text: text, happenedAt: at(hms), replyTarget: target)
    }

    /// A weather event starting at `hms`.
    static func event(_ hms: String, _ text: String) throws -> TownEvent {
        try event(hms, text, kind: weather, resident: nil)
    }

    /// An event of `kind` starting at `hms`.
    static func event(_ hms: String, _ text: String, kind: EventKindID) throws -> TownEvent {
        try event(hms, text, kind: kind, resident: nil)
    }

    /// An event of `kind` starting at `hms` and lasting an hour, about `resident` if one
    /// is given.
    static func event(
        _ hms: String,
        _ text: String,
        kind: EventKindID,
        resident: Resident.ID?,
    ) throws -> TownEvent {
        let start = at(hms)
        return try TownEvent(
            id: TownEvent.ID(),
            kind: kind,
            description: text,
            startsAt: start,
            endsAt: start.addingTimeInterval(anHour),
            relatedResident: resident,
        )
    }

    /// The timeline's world in a test: a manual clock and the date it reads, the POSIX
    /// English locale, a UTC Gregorian calendar, and `pageSize` rows a page.
    static func environment(clock: ManualClock, pageSize: Int) -> TimelineEnvironment {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(identifier: "UTC") {
            calendar.timeZone = utc
        }
        return TimelineEnvironment(
            clock: clock,
            now: { clock.date },
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            pageSize: pageSize,
        )
    }

    /// A timeline over `snapshot` with no store, on `clock`, for you named "Tomo".
    @MainActor
    static func model(
        _ snapshot: TimelineSnapshot,
        clock: ManualClock,
    ) throws -> TimelineViewModel {
        try model(snapshot, clock: clock, displayName: DisplayName("Tomo"))
    }

    /// A timeline over `snapshot` with no store, on `clock`, for you named
    /// `displayName`; the snapshot knows ``names`` besides its own.
    @MainActor
    static func model(
        _ snapshot: TimelineSnapshot,
        clock: ManualClock,
        displayName: DisplayName?,
    ) -> TimelineViewModel {
        var snapshot = snapshot
        snapshot.residentNames.merge(names) { given, _ in given }
        return TimelineViewModel(
            snapshot: snapshot,
            displayName: displayName,
            eventSymbols: symbols,
            environment: environment(clock: clock, pageSize: pageSize),
        )
    }

    /// A timeline over `store` on `clock`, for you named "Tomo", 100 rows a page.
    @MainActor
    static func model(store: TownStore, clock: ManualClock) throws -> TimelineViewModel {
        try model(store: store, clock: clock, pageSize: pageSize)
    }

    /// A timeline over `store` on `clock`, for you named "Tomo", `pageSize` rows a page.
    @MainActor
    static func model(
        store: TownStore,
        clock: ManualClock,
        pageSize: Int,
    ) throws -> TimelineViewModel {
        try TimelineViewModel(
            store: store,
            displayName: DisplayName("Tomo"),
            eventSymbols: symbols,
            environment: environment(clock: clock, pageSize: pageSize),
        )
    }
}

/// Runs `model` until `body` returns, waiting first for its first sleep — by then it has
/// loaded what it shows and is following the store and the clock.
@MainActor
func whileRunning(
    _ model: TimelineViewModel,
    on clock: ManualClock,
    _ body: () async throws -> Void,
) async throws {
    let running = Task { await model.run() }
    defer { running.cancel() }
    await clock.waitForSleep(1)
    try await body()
}

extension TimelineViewModel {
    /// The post groups, top to bottom.
    var groups: [TimelinePostGroup] {
        items.compactMap { item in
            if case let .group(group) = item {
                return group
            }
            return nil
        }
    }

    /// Each row top to bottom as a line a test can compare to a literal: a group as its
    /// posts' texts joined by " / ", led by "↩ " and the quoted text when it has a quote
    /// line; an event row as "event: " and its text.
    var outline: [String] {
        items.map { item in
            switch item {
            case let .group(group):
                let posts = group.posts.map(\.text).joined(separator: " / ")
                guard let quote = group.quote else {
                    return posts
                }
                return "↩ \(quote.text) | \(posts)"

            case let .event(event):
                return "event: \(event.text)"
            }
        }
    }

    /// Every post's text, top to bottom.
    var postTexts: [String] {
        groups.flatMap { $0.posts.map(\.text) }
    }
}
