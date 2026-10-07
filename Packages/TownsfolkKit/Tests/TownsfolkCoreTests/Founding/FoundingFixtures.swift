import Foundation
import FoundationModels
import os
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// What one founding run reported, in the order it reported it.
final class ProgressLog: Sendable {
    private let steps = OSAllocatedUnfairLock<[FoundingProgress]>(initialState: [])

    var reported: [FoundingProgress] {
        steps.withLock { $0 }
    }

    func record(_ step: FoundingProgress) {
        steps.withLock { $0.append(step) }
    }
}

/// Values the founding suites share: a small seed table, the generators that draw from
/// it, the model's scripted answers, and a founder wired to a fresh store.
enum FoundingFixtures {
    /// A generator whose every draw is the first choice: `next()` answers 1, so
    /// `Int.random(in: 0 ..< n)` is always 0 and `shuffled()` keeps the order. With it,
    /// founding draws the lowest combination of axes not excluded, the first residents as
    /// speakers, and their profile aspects in declaration order, so every expectation
    /// below is worked out by hand.
    struct FirstChoice: RandomNumberGenerator {
        mutating func next() -> UInt64 {
            1
        }
    }

    /// SplitMix64: a seeded generator for the tests that hold an invariant across many
    /// draws rather than one expected value.
    struct SplitMix: RandomNumberGenerator {
        private static let increment: UInt64 = 0x9E37_79B9_7F4A_7C15
        private static let firstMultiplier: UInt64 = 0xBF58_476D_1CE4_E5B9
        private static let secondMultiplier: UInt64 = 0x94D0_49BB_1331_11EB
        private static let firstShift: UInt64 = 30
        private static let secondShift: UInt64 = 27
        private static let thirdShift: UInt64 = 31

        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= Self.increment
            var value = state
            value = (value ^ (value >> Self.firstShift)) &* Self.firstMultiplier
            value = (value ^ (value >> Self.secondShift)) &* Self.secondMultiplier
            return value ^ (value >> Self.thirdShift)
        }
    }

    /// One model answer to script, by what it stands for.
    enum Answer {
        case failure(ModelCallError)
        case resident(NewResidentDraft)
        case scene([DraftPost])
        case town(TownDraft)
    }

    /// More rows than a founded town's timeline holds.
    static let pageLimit = 10
    /// 2026-10-01T10:00:00Z, the moment every founding test runs at.
    static let now = StoreFixtures.date("2026-10-01T10:00:00Z")

    /// Six occupations varying fastest, then two of each other axis — so the first-choice
    /// generator draws baker, librarian, and potter, all cheerful young adults who fish,
    /// and a redraw that excludes those three draws florist, barber, and nurse.
    static let occupations = ["baker", "librarian", "potter", "florist", "barber", "nurse"]

    static var maplewood: TownDraft {
        TownDraft(
            name: "Maplewood",
            setting: "A small town by a slow river. Mornings smell of bread.",
            places: ["the bakery", "the river", "the station"],
        )
    }

    static var mika: NewResidentDraft {
        NewResidentDraft(name: "Mika", worry: "the oven cooling too early", relationships: [])
    }

    static var jun: NewResidentDraft {
        NewResidentDraft(
            name: "Jun",
            worry: "the leaky library roof",
            relationships: [.init(name: "Mika", description: "Buys bread from her every morning.")],
        )
    }

    static var sora: NewResidentDraft {
        NewResidentDraft(name: "Sora", worry: "the price of clay", relationships: [])
    }

    /// A two-post scene by Mika, the second replying to the first.
    static var welcome: [DraftPost] {
        [
            DraftPost(speaker: "Mika", text: "Fresh loaves are out."),
            DraftPost(speaker: "Mika", text: "Come early tomorrow.", replyTo: "S1"),
        ]
    }

    /// Maplewood, Mika, Jun, Sora, and ``welcome``: a founding that succeeds first time.
    static var happyPath: [Answer] {
        [.town(maplewood), .resident(mika), .resident(jun), .resident(sora), .scene(welcome)]
    }

    /// A seed table small enough to reason about by hand: ``occupations``, then two
    /// personalities, life stages, and hobbies.
    static func tables() throws -> SeedTables {
        try tables(
            occupations: occupations,
            personalities: ["cheerful", "shy"],
            lifeStages: ["young adult", "retired"],
            hobbies: ["fishing", "chess"],
        )
    }

    /// A seed table with these axes and no event kinds.
    static func tables(
        occupations: [String],
        personalities: [String],
        lifeStages: [String],
        hobbies: [String],
    ) throws -> SeedTables {
        func entries(_ texts: [String]) -> [[String: String]] {
            texts.map { ["id": $0.replacing(" ", with: "-"), "text": $0] }
        }
        let file: [String: Any] = [
            "version": SeedTables.formatVersion,
            "residentAxes": [
                "occupations": entries(occupations),
                "personalities": entries(personalities),
                "lifeStages": entries(lifeStages),
                "hobbies": entries(hobbies),
            ],
            "eventKinds": [],
            "fixedEventKinds": [["id": "founding", "symbol": "house"]],
        ]
        return try SeedTables.decode(JSONSerialization.data(withJSONObject: file))
    }

    /// The fake's outcome for each answer, in order.
    static func outcomes(_ answers: [Answer]) -> [FakeLanguageModelProvider.Outcome] {
        answers.map { answer in
            switch answer {
            case let .town(draft):
                .content(draft.generatedContent)

            case let .resident(draft):
                .content(draft.generatedContent)

            case let .scene(posts):
                .content(WritingFixtures.content(posts))

            case let .failure(error):
                .failure(error)
            }
        }
    }

    /// An available fake answering `answers` in order.
    static func fake(_ answers: [Answer]) -> FakeLanguageModelProvider {
        WritingFixtures.fake(outcomes(answers))
    }
}

/// A founder over `fake` and `store`, at ``FoundingFixtures/now``, drawing with the
/// first-choice generator from ``FoundingFixtures/tables()``.
func founder(_ fake: FakeLanguageModelProvider, store: TownStore) throws -> Founder {
    try founder(
        fake,
        store: store,
        generator: FoundingFixtures.FirstChoice(),
        tables: FoundingFixtures.tables(),
    )
}

/// A founder over `fake` and `store`, at ``FoundingFixtures/now``, drawing with
/// `generator` from `tables`.
func founder(
    _ fake: FakeLanguageModelProvider,
    store: TownStore,
    generator: any RandomNumberGenerator & Sendable,
    tables: SeedTables,
) -> Founder {
    Founder(
        model: fake,
        writer: SceneWriter(model: fake, store: store),
        seeds: tables,
        store: store,
        now: { FoundingFixtures.now },
        generator: generator,
    )
}

/// Founds as Tomo with `founder`.
func found(with founder: Founder) async throws -> FoundingOutcome {
    try await found(with: founder, log: ProgressLog())
}

/// Founds as Tomo with `founder`, recording progress into `log`.
func found(with founder: Founder, log: ProgressLog) async throws -> FoundingOutcome {
    try await founder.found(displayName: DisplayName("Tomo")) { step in
        log.record(step)
    }
}

/// Every timeline row in `store`, newest first — a founded town has three.
func timeline(in store: TownStore) async throws -> [TimelineEntry] {
    try await store.page(before: nil, limit: FoundingFixtures.pageLimit).entries
}

/// Expects `store` to hold nothing at all: no town, resident, schedule, or row.
func expectEmpty(_ store: TownStore) async throws {
    #expect(try await store.town() == nil)
    #expect(try await store.residents().isEmpty)
    #expect(try await store.schedule() == nil)
    #expect(try await timeline(in: store).isEmpty)
}

extension FakeLanguageModelProvider {
    /// The prompts of the calls made so far, in order.
    var prompts: [String] {
        calls.map(\.prompt)
    }
}
