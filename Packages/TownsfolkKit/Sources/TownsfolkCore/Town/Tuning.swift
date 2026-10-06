/// Every starting value the requirements mark † — the numbers only running the real
/// model on a real Mac can settle (requirements.md:13) — in one place, so tuning the
/// town is an edit here rather than a hunt through method bodies.
///
/// A type that obeys one of these takes a `Tuning` in its initializer, defaulting to
/// ``default``, so a test hands it a smaller one to reach a boundary quickly
/// (`designing-core-logic` › One `Tuning` type). A domain invariant that is not a
/// starting value — a resident's name ≤ 20, an event's description ≤ 120 — is a constant
/// on its type instead. Line references (`:137`) are to `docs/product/requirements.md`.
public struct Tuning: Sendable, Equatable {
    /// Founding a town and naming yourself (§3.1).
    public struct Founding: Sendable, Equatable {
        /// Your display name, in characters after trimming (:137, :332).
        public var displayNameLength = 1 ... 20
        /// The longest town name the model may invent, in characters (:138).
        public var townNameMaxLength = 30
        /// How many named places a town has (:138).
        public var placeCount = 3 ... 5
        /// Residents invented at founding — also the starting population (:138, :258).
        public var foundingResidentCount = 3
        /// Founding attempts in total before the failure is shown (:144;
        /// `docs/product/ux-flows.md:195`).
        public var foundingAttempts = 3
    }

    /// How the timeline shows a scene (§3.2, §3.3).
    public struct Timeline: Sendable, Equatable {
        /// The gap between a scene's posts as they appear, as a fraction of the scene
        /// interval (:167).
        public var revealSpacing = 0.10 ... 0.30
        /// The longest post a resident may write, in characters (:168).
        public var residentPostMaxLength = 280
        /// Lines the status line takes; what does not fit is truncated (:188).
        public var statusLineLineLimit = 1
    }

    /// How often ordinary scenes come (§3.4).
    public struct Pace: Sendable, Equatable {
        /// The time between ordinary scenes — Fast 1 minute, Normal 6, Slow 30
        /// (:199–:203).
        public var sceneInterval: PerSpeed<Duration>
        /// How far an interval may stray either way, as a fraction of it, so the town
        /// never ticks like a clock (:205).
        public var sceneIntervalJitter = 0.5

        init() {
            let fastMinutes = 1
            let normalMinutes = 6
            let slowMinutes = 30
            sceneInterval = PerSpeed(
                fast: .minutes(fastMinutes),
                normal: .minutes(normalMinutes),
                slow: .minutes(slowMinutes),
            )
        }
    }

    /// Your posts and the responses they draw (§3.5).
    public struct YourPost: Sendable, Equatable {
        /// Your post, in characters after trimming (:223).
        public var yourPostLength = 1 ... 140
        /// When the first response comes at Normal — 2 to 10 minutes (:227).
        public var firstResponseDelay: ClosedRange<Duration>
        /// What response delays are multiplied by — halved at Fast, doubled at Slow
        /// (:227).
        public var responseDelayScale: PerSpeed<Double>
        /// How many response scenes one post draws (:228).
        public var responseSceneCount = 1 ... 3
        /// The relative odds of 1, 2, or 3 response scenes, in that order — 3 : 2 : 1,
        /// "falling likelihood" (:228; chosen in planning for #26, adjusted in use).
        public var responseSceneWeights: [Int]
        /// How long a post's responses spread over at Normal — about an hour (:228).
        public var responseSpan: Duration
        /// How long a post stays a possible seed for ordinary scenes — about a day
        /// (:229).
        public var postSeedLifetime: Duration
        /// The share of ordinary scenes seeded by a still-live post of yours (:229).
        public var postSeedChance = 0.05
        /// How often the resident you replied to speaks first in the first response
        /// (:230).
        public var repliedResidentSpeaksFirstChance = 0.70
        /// Your latest posts that keep scheduled responses; a newer one drops the
        /// oldest schedule (:231).
        public var maxPostsAwaitingResponses = 3

        init() {
            let earliestMinutes = 2
            let latestMinutes = 10
            firstResponseDelay = .minutes(earliestMinutes) ... .minutes(latestMinutes)
            let fastScale = 0.5
            let normalScale = 1.0
            let slowScale = 2.0
            responseDelayScale = PerSpeed(fast: fastScale, normal: normalScale, slow: slowScale)
            let oneScene = 3
            let twoScenes = 2
            let threeScenes = 1
            responseSceneWeights = [oneScene, twoScenes, threeScenes]
            let spanHours = 1
            responseSpan = .hours(spanHours)
            let lifetimeHours = 24
            postSeedLifetime = .hours(lifetimeHours)
        }
    }

    /// Events (§3.6).
    public struct Events: Sendable, Equatable {
        /// About how often a new event starts, in running time — about 3 hours (:254).
        public var eventInterval: Duration
        /// How long an event lasts in town time — 1 to 12 hours; each kind picks within
        /// it (:255).
        public var eventDuration: ClosedRange<Duration>
        /// Events ongoing at once (:255).
        public var maxOngoingEvents = 2

        init() {
            let intervalHours = 3
            eventInterval = .hours(intervalHours)
            let durationHours = 1 ... 12
            eventDuration = .hours(durationHours.lowerBound) ... .hours(durationHours.upperBound)
        }
    }

    /// Population and moves (§3.6).
    public struct Residents: Sendable, Equatable {
        /// How many residents live in town at once (:258).
        public var population = 3 ... 10
        /// About how often someone moves in or out, in running time — 1 to 2 days
        /// (:258).
        public var moveInterval: ClosedRange<Duration>
        /// The chance a newcomer is seeded from a name you brought up that no living
        /// resident holds (:232, :259; chosen in planning for #28, adjusted in use).
        public var newcomerFromNameChance = 0.5

        init() {
            let intervalHours = 24 ... 48
            moveInterval = .hours(intervalHours.lowerBound) ... .hours(intervalHours.upperBound)
        }
    }

    /// What happens after a pause (§3.7).
    public struct CatchUp: Sendable, Equatable {
        /// Scene intervals of pause per catch-up scene — also the shortest pause that
        /// invents anything (:278, :281).
        public var catchUpIntervalsPerScene = 4
        /// The most catch-up scenes after any pause, so weeks away never flood (:278).
        public var catchUpMaxScenes = 5
        /// The shortest pause that brings news, an event or a move — 2 hours (:279).
        public var catchUpNewsPause: Duration
        /// New events after a long pause (:279).
        public var catchUpMaxEvents = 1
        /// Moves after a long pause (:279).
        public var catchUpMaxMoves = 1

        init() {
            let newsPauseHours = 2
            catchUpNewsPause = .hours(newsPauseHours)
        }
    }

    /// Talking to the on-device model (§3.8, §3.11).
    public struct Generation: Sendable, Equatable {
        /// How far back a scene's context reaches for recent posts — about a day (:307).
        public var recentContextWindow: Duration
        /// Retries with a new seed after a refusal before the turn is skipped (:349).
        public var refusalRetriesPerTurn = 2
        /// Refusals in a row with something in the context before it is left out
        /// (:350).
        public var refusalsBeforeLeftOut = 3
        /// Tokens held back from the context budget for the schema and the answer
        /// (:351, :413; chosen in planning for #14, adjusted in use).
        public var outputTokenReserve = 1_024

        init() {
            let windowHours = 24
            recentContextWindow = .hours(windowHours)
        }
    }

    /// The starting values the app ships with.
    public static let `default` = Self()

    /// Founding a town and naming yourself (§3.1).
    public var founding = Founding()
    /// How the timeline shows a scene (§3.2, §3.3).
    public var timeline = Timeline()
    /// How often ordinary scenes come (§3.4).
    public var pace = Pace()
    /// Your posts and the responses they draw (§3.5).
    public var yourPost = YourPost()
    /// Events (§3.6).
    public var events = Events()
    /// Population and moves (§3.6).
    public var residents = Residents()
    /// What happens after a pause (§3.7).
    public var catchUp = CatchUp()
    /// Talking to the on-device model (§3.8, §3.11).
    public var generation = Generation()
}

/// The units the requirements write their durations in, so each `Tuning` value reads as
/// written (6 minutes, 24 hours) rather than as a count of seconds.
extension Duration {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3_600

    static func minutes(_ count: Int) -> Self {
        .seconds(count * secondsPerMinute)
    }

    static func hours(_ count: Int) -> Self {
        .seconds(count * secondsPerHour)
    }
}
