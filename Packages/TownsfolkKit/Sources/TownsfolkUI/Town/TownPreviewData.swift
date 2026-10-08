import SwiftUI
import TownsfolkCore

/// Window sizes the previews show the timeline at.
private enum PreviewSize {
    static let minimumWidth = DesignLock.Window.minimumWidth
    static let minimumHeight = DesignLock.Window.minimumHeight
    static let defaultHeight = DesignLock.Window.defaultHeight
    /// Wider than the 560 pt column and its 16 pt margins, so the column centers.
    static let wideWidth: CGFloat = 900
}

/// How long ago, in seconds, each preview post happened.
private enum Ago {
    static let seconds: TimeInterval = 10
    static let halfMinute: TimeInterval = 30
    static let minute: TimeInterval = 60
    static let rain: TimeInterval = 720
    static let yourPost: TimeInterval = 1_500
    static let oven: TimeInterval = 2_400
    static let ovenReply: TimeInterval = 2_280
    static let anHour: TimeInterval = 3_600
    static let move: TimeInterval = 7_200
    static let founding: TimeInterval = 93_600
}

/// Timelines in each state worth seeing, built from snapshots so a preview never reads or
/// writes a store. Times are relative to now, so the rows read as they would in use.
@MainActor
private enum TownPreviewData {
    static let mika = Resident.ID()
    static let jun = Resident.ID()
    static let sora = Resident.ID()
    static let hana = Resident.ID()
    static let weather = EventKindID(rawValue: "weather-turns")
    static let symbols: [EventKindID: String] = [
        .founding: "house",
        .moveIn: "house",
        .moveOut: "figure.walk",
        weather: "cloud.sun.rain",
    ]

    /// Mika's post the busy timeline's newest scene replies to.
    static let ovenPostID = Post.ID()
    /// Your post in the busy timeline.
    static let yourPostID = Post.ID()

    static func ago(_ seconds: TimeInterval) -> Date {
        Date.now.addingTimeInterval(-seconds)
    }

    static func post(
        _ author: Resident.ID,
        _ seconds: TimeInterval,
        _ text: String,
        scene: SceneID,
        replyTo target: Post.ID?,
    ) throws -> Post {
        try Post(
            id: Post.ID(),
            author: .resident(author),
            text: text,
            happenedAt: ago(seconds),
            replyTarget: target,
            origin: .ordinary,
            sceneID: scene,
        )
    }

    static func event(
        _ kind: EventKindID,
        _ seconds: TimeInterval,
        _ text: String,
        about resident: Resident.ID?,
    ) throws -> TownEvent {
        try TownEvent(
            id: TownEvent.ID(),
            kind: kind,
            description: text,
            startsAt: ago(seconds),
            endsAt: ago(seconds).addingTimeInterval(Ago.anHour),
            relatedResident: resident,
        )
    }

    /// "You moved to Maplewood." and the first scene above it.
    static func foundingEntries() throws -> [TimelineEntry] {
        let scene = SceneID()
        return try [
            .event(event(.founding, Ago.founding, "You moved to Maplewood.", about: nil)),
            .post(post(mika, Ago.founding, "Welcome to Maplewood.", scene: scene, replyTo: nil)),
            .post(post(
                jun,
                Ago.founding - Ago.minute,
                "The bakery opens at seven.",
                scene: scene,
                replyTo: nil,
            )),
        ]
    }

    /// A day of the town: a scene, a move, your post, rain, and a scene quoting an older
    /// post.
    static func busyEntries() throws -> [TimelineEntry] {
        let ovenScene = SceneID()
        let oven = try Post(
            id: ovenPostID,
            author: .resident(mika),
            text: "The oven made a goose noise again.",
            happenedAt: ago(Ago.oven),
            origin: .ordinary,
            sceneID: ovenScene,
        )
        let yours = try Post(
            id: yourPostID,
            author: .you,
            text: "Learning Rust today. Wish me luck.",
            happenedAt: ago(Ago.yourPost),
        )
        let newest = SceneID()
        return try foundingEntries() + [
            .event(event(.moveIn, Ago.move, "Hana moved in above the café.", about: hana)),
            .post(oven),
            .post(post(jun, Ago.ovenReply, "Is that… good?", scene: ovenScene, replyTo: oven.id)),
            .post(yours),
            .event(event(weather, Ago.rain, "It started raining.", about: nil)),
            .post(post(
                jun,
                Ago.minute,
                "Told you. Get there before eight.",
                scene: newest,
                replyTo: oven.id,
            )),
            .post(post(
                sora,
                Ago.halfMinute,
                "Or ask Mika to save you one?",
                scene: newest,
                replyTo: nil,
            )),
        ]
    }

    static func model(_ build: (inout TimelineSnapshot) throws -> Void) -> TimelineViewModel? {
        do {
            var snapshot = TimelineSnapshot(entries: [])
            snapshot.townName = "Maplewood"
            snapshot.residentNames = [mika: "Mika", jun: "Jun", sora: "Sora", hana: "Hana"]
            try build(&snapshot)
            return try TimelineViewModel(
                snapshot: snapshot,
                displayName: DisplayName("Tomo"),
                eventSymbols: symbols,
                environment: TimelineEnvironment(),
            )
        } catch {
            return nil
        }
    }

    static func justFounded() -> TimelineViewModel? {
        model { $0.entries = try foundingEntries() }
    }

    static func busy() -> TimelineViewModel? {
        model { $0.entries = try busyEntries() }
    }

    /// The newest scene's first post just arrived under its wash; the second is an hour
    /// away, so the group stays one post long.
    static func midReveal() -> TimelineViewModel? {
        model { snapshot in
            let scene = SceneID()
            snapshot.entries = try busyEntries() + [
                .post(post(sora, -Ago.anHour, "Gerald suits it.", scene: scene, replyTo: nil)),
            ]
            snapshot.arrivedLive = try [
                .post(post(
                    mika,
                    Ago.seconds,
                    "I named the oven Gerald.",
                    scene: scene,
                    replyTo: nil,
                )),
            ]
        }
    }

    /// Three posts arrived while you read older ones.
    static func newPosts() -> TimelineViewModel? {
        model { snapshot in
            snapshot.entries = try busyEntries()
            snapshot.arrivedWhileAway = try [
                .post(post(mika, Ago.seconds, "Gerald it is.", scene: SceneID(), replyTo: nil)),
                .post(post(jun, Ago.seconds, "Who is Gerald?", scene: SceneID(), replyTo: nil)),
                .post(post(
                    sora,
                    Ago.seconds,
                    "The oven, apparently.",
                    scene: SceneID(),
                    replyTo: nil,
                )),
            ]
        }
    }

    /// Your post selected with the keyboard.
    static func selected() -> TimelineViewModel? {
        model { snapshot in
            snapshot.entries = try busyEntries()
            snapshot.selectedPost = yourPostID
        }
    }
}

/// The town window over `model`, with an empty composer, or a note to the developer when
/// its posts could not be built.
@MainActor
@ViewBuilder
private func town(_ model: TimelineViewModel?) -> some View {
    if let model {
        TownView(
            model: model,
            composer: ComposerViewModel(text: "", replyTarget: nil),
            statusLine: StatusLineViewModel(
                content: StatusLineContent(
                    line: .eventAndTopic(event: "You moved to Maplewood.", topic: "the bakery"),
                    eventKind: .founding,
                ),
                eventSymbols: TownPreviewData.symbols,
                environment: TimelineEnvironment(),
            ),
        )
    } else {
        Text(verbatim: "Preview: could not build the timeline's posts.")
    }
}

#Preview("Just founded") {
    town(TownPreviewData.justFounded())
}

#Preview("Busy") {
    town(TownPreviewData.busy())
}

#Preview("Busy, dark") {
    town(TownPreviewData.busy())
        .preferredColorScheme(.dark)
}

#Preview("Group mid-reveal") {
    town(TownPreviewData.midReveal())
}

#Preview("Group mid-reveal, dark") {
    town(TownPreviewData.midReveal())
        .preferredColorScheme(.dark)
}

#Preview("New posts pill") {
    town(TownPreviewData.newPosts())
}

#Preview("New posts pill, dark") {
    town(TownPreviewData.newPosts())
        .preferredColorScheme(.dark)
}

#Preview("Selected post") {
    town(TownPreviewData.selected())
}

#Preview("Busy, 320 × 440") {
    town(TownPreviewData.busy())
        .frame(width: PreviewSize.minimumWidth, height: PreviewSize.minimumHeight)
}

#Preview("Busy, 900 pt wide") {
    town(TownPreviewData.busy())
        .frame(width: PreviewSize.wideWidth, height: PreviewSize.defaultHeight)
}
