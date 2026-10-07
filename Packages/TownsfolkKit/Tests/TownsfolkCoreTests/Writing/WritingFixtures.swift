import Foundation
import FoundationModels
import TownsfolkCore
import TownsfolkTestSupport

/// The town every writer suite writes in: Maplewood, three living residents and one who
/// moved out, and one name you brought up that Mika took up as an interest. Each profile
/// differs, so a prompt snapshot shows whose is whose.
struct WritingCast {
    let rust: Interest
    let mika: Resident
    let jun: Resident
    let aki: Resident
    let sora: Resident

    /// The roster a request carries: the living residents, then the past one.
    var residents: [Resident] {
        [mika, jun, aki, sora]
    }

    init() throws {
        rust = try InterestDraft(term: "Rust").make()
        mika = try Resident(
            id: Resident.ID(),
            name: "Mika",
            profile: Resident.Profile(
                ageGroup: "thirties",
                occupation: "baker",
                hobby: "fishing",
                worry: "the rent",
                personality: "cheerful",
            ),
            movedInAt: StoreFixtures.morning,
            interests: [rust.id],
        )
        jun = try Resident(
            id: Resident.ID(),
            name: "Jun",
            profile: Resident.Profile(
                ageGroup: "twenties",
                occupation: "librarian",
                hobby: "chess",
                worry: "a leaky roof",
                personality: "shy",
            ),
            movedInAt: StoreFixtures.morning,
        )
        aki = try Self.resident("Aki")
        sora = try Self.resident("Sora", movedOut: true)
    }

    private static func resident(_ name: String, movedOut: Bool = false) throws -> Resident {
        try Resident(
            id: Resident.ID(),
            name: name,
            profile: StoreFixtures.profile(),
            movedInAt: StoreFixtures.morning,
            status: movedOut ? .movedOut : .living,
            movedOutAt: movedOut ? StoreFixtures.minutes(1) : nil,
        )
    }

    /// The town founded with this cast: an ended founding event, so no event is ongoing,
    /// and a first scene that only records ``rust``.
    func founding() throws -> TownStore.FoundingStep {
        try TownStore.FoundingStep(
            town: WritingFixtures.town(),
            residents: residents,
            foundingEvent: TownEvent(
                id: TownEvent.ID(),
                kind: .founding,
                description: "You moved to Maplewood.",
                startsAt: StoreFixtures.morning,
                endsAt: StoreFixtures.morning,
                status: .ended,
            ),
            schedule: Schedule(
                nextOrdinarySceneDue: StoreFixtures.firstDue,
                lastRanAt: StoreFixtures.morning,
            ),
            firstScene: TownStore.SceneStep(posts: [], interests: [rust]),
        )
    }

    /// A request by `speakers` about `seeds`, from you, named Tomo, in Maplewood.
    func request(speakers: [Resident], seeds: [SceneSeed]) throws -> SceneRequest {
        try SceneRequest(
            you: DisplayName("Tomo"),
            town: WritingFixtures.town(),
            residents: residents,
            speakers: speakers.map(\.id),
            seeds: seeds,
        )
    }

    /// A post by `resident` in a scene of its own, `minute` minutes after nine.
    func post(by resident: Resident, _ text: String, minute: Int) throws -> Post {
        try ResidentPostDraft(author: resident.id, time: StoreFixtures.minutes(minute), text: text)
            .make()
    }
}

/// One post the scripted model writes.
struct DraftPost {
    var speaker: String
    var text: String
    var replyTo: String?
}

/// Values the writer suites share.
enum WritingFixtures {
    /// 2026-10-01T12:00:00Z — three hours after nine, so every fixture post is inside the
    /// recent window.
    static let now = StoreFixtures.date("2026-10-01T12:00:00Z")
    /// A context size no fixture prompt comes near.
    static let roomyContextSize = 100_000

    /// A short, valid answer by Mika.
    static var mikaSpeaks: GeneratedContent {
        content([DraftPost(speaker: "Mika", text: "Rain again.")])
    }

    static func town() throws -> Town {
        try Town(
            name: "Maplewood",
            setting: "A small town by a slow river.",
            places: ["the bakery", "the river", "the station"],
            foundedAt: StoreFixtures.morning,
        )
    }

    /// The model's answer: `posts` and no topic tag, as generated content.
    static func content(_ posts: [DraftPost]) -> GeneratedContent {
        content(posts, tags: [])
    }

    /// The model's answer: `posts` and `tags`, as generated content.
    static func content(_ posts: [DraftPost], tags: [String]) -> GeneratedContent {
        let drafts = posts.map { post in
            SceneDraft.PostDraft(speaker: post.speaker, text: post.text, replyTo: post.replyTo)
        }
        return SceneDraft(posts: drafts, topicTags: tags).generatedContent
    }

    /// An available fake with a roomy context and `outcomes` queued.
    static func fake(_ outcomes: [FakeLanguageModelProvider.Outcome]) -> FakeLanguageModelProvider {
        fake(outcomes, contextSize: roomyContextSize)
    }

    /// An available fake with `contextSize` tokens and `outcomes` queued.
    static func fake(
        _ outcomes: [FakeLanguageModelProvider.Outcome],
        contextSize: Int,
    ) -> FakeLanguageModelProvider {
        FakeLanguageModelProvider(
            availability: .available,
            contextSize: contextSize,
            outcomes: outcomes,
            holdsResponses: false,
        )
    }

    /// `count` refusals.
    static func refusals(_ count: Int) -> [FakeLanguageModelProvider.Outcome] {
        Array(repeating: .failure(.refused), count: count)
    }
}

/// Runs `body` with a store holding ``WritingCast/founding()`` and nothing else.
func withWritingStore(_ body: (TownStore, WritingCast) async throws -> Void) async throws {
    try await withStore { store, _ in
        let cast = try WritingCast()
        try await store.found(cast.founding())
        try await body(store, cast)
    }
}
