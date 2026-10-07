import Foundation
import FoundationModels
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// One turn by Aki about the new bread, against a fresh fake: the knobs a budget test
/// turns, each with the value most tests want.
private struct BudgetRun {
    typealias Call = FakeLanguageModelProvider.Call

    var contextSize = WritingFixtures.roomyContextSize
    var outcomes: [FakeLanguageModelProvider.Outcome] = [.content(WriterBudgetTests.akiSpeaks)]
    var seeds: [SceneSeed] = [.topic("new bread")]

    func write(in store: TownStore) async throws -> (SceneOutcome, [Call]) {
        let cast = try WritingCast()
        let fake = WritingFixtures.fake(outcomes, contextSize: contextSize)
        let writer = SceneWriter(model: fake, store: store)
        let request = try cast.request(speakers: [cast.aki], seeds: seeds)
        let outcome = try await writer.write(request, at: WritingFixtures.now)
        return (outcome, fake.calls)
    }

    func calls(in store: TownStore) async throws -> [FakeLanguageModelProvider.Call] {
        try await write(in: store).1
    }
}

/// The context budget (REQ-005, REQ-006): the prompt is fitted to the context size minus
/// the output reserve by dropping recent posts, oldest first; an overflow the model
/// reports is retried once with half the posts.
///
/// The fake counts one token per `Character`, and every recent post here is one of nine
/// notes of yours whose line, `P1 Tomo: "Note A."` and its line break, is 19 characters —
/// so dropping `n` posts saves exactly `19 × n` tokens.
@Suite("SceneWriter budget")
struct WriterBudgetTests {
    static let notes = ["A", "B", "C", "D", "E", "F", "G", "H", "I"].map { "Note \($0)." }
    /// `Tuning.generation.outputTokenReserve`'s starting value (requirements.md:413).
    static let reserve = 1_024
    static let lineLength = 19

    static var akiSpeaks: GeneratedContent {
        WritingFixtures.content([DraftPost(speaker: "Aki", text: "Hello.")])
    }

    /// Stores the nine notes, a minute apart, oldest first.
    static func storeNotes(in store: TownStore) async throws {
        for (minute, note) in notes.enumerated() {
            let post = try YourPostDraft(time: StoreFixtures.minutes(minute), text: note).make()
            try await store.storeYourPost(post)
        }
    }

    /// The notes each call carried, oldest first.
    static func notesCarried(by calls: [FakeLanguageModelProvider.Call]) -> [[String]] {
        calls.map { call in notes.filter { call.prompt.contains("\"\($0)\"") } }
    }

    /// What the fake counts for `call`.
    static func tokens(_ call: FakeLanguageModelProvider.Call) -> Int {
        call.instructions.count + call.prompt.count
    }

    @Test
    func `a prompt within the budget carries every recent post`() async throws {
        try await withStore { store, _ in
            try await Self.storeNotes(in: store)
            let (outcome, calls) = try await BudgetRun().write(in: store)
            #expect(Self.notesCarried(by: calls) == [Self.notes])
            #expect(outcome != .skipped(.overflow))
        }
    }

    @Test
    func `a prompt exactly at the budget is sent unchanged, and one token over drops the oldest`(
    ) async throws {
        try await withStore { store, _ in
            try await Self.storeNotes(in: store)
            let full = try #require(await BudgetRun().calls(in: store).first)
            let atBudget = Self.tokens(full) + Self.reserve

            let exact = try await BudgetRun(contextSize: atBudget).calls(in: store)
            let over = try await BudgetRun(contextSize: atBudget - 1).calls(in: store)

            let allButA = [
                "Note B.", "Note C.", "Note D.", "Note E.", "Note F.", "Note G.", "Note H.",
                "Note I.",
            ]
            #expect(exact == [full])
            #expect(Self.notesCarried(by: over) == [allButA])
        }
    }

    @Test
    func `posts are dropped oldest first until the prompt fits`() async throws {
        try await withStore { store, _ in
            try await Self.storeNotes(in: store)
            let full = try #require(await BudgetRun().calls(in: store).first)
            let threeFewer = Self.tokens(full) + Self.reserve - 3 * Self.lineLength

            let six = try await BudgetRun(contextSize: threeFewer).calls(in: store)
            let five = try await BudgetRun(contextSize: threeFewer - 1).calls(in: store)

            let fromD = ["Note D.", "Note E.", "Note F.", "Note G.", "Note H.", "Note I."]
            let fromE = ["Note E.", "Note F.", "Note G.", "Note H.", "Note I."]
            #expect(Self.notesCarried(by: six) == [fromD])
            #expect(Self.notesCarried(by: five) == [fromE])
        }
    }

    @Test
    func `a fixed part that fits alone is sent without posts, and one over it skips without a call`(
    ) async throws {
        try await withStore { store, _ in
            let bare = try #require(await BudgetRun().calls(in: store).first)
            try await Self.storeNotes(in: store)
            let fixed = Self.tokens(bare) + Self.reserve

            let alone = try await BudgetRun(contextSize: fixed).calls(in: store)
            let (outcome, none) = try await BudgetRun(contextSize: fixed - 1).write(in: store)

            #expect(alone == [bare])
            #expect(outcome == .skipped(.overflow))
            #expect(none.isEmpty)
        }
    }

    @Test
    func `an overflow the model reports is retried once with half the posts, rounded down`(
    ) async throws {
        try await withStore { store, _ in
            try await Self.storeNotes(in: store)
            let run = BudgetRun(outcomes: [
                .failure(.contextSizeExceeded),
                .content(Self.akiSpeaks),
            ])

            let (outcome, calls) = try await run.write(in: store)

            let fromF = ["Note F.", "Note G.", "Note H.", "Note I."]
            #expect(Self.notesCarried(by: calls) == [Self.notes, fromF])
            #expect(outcome != .skipped(.overflow))
        }
    }

    @Test
    func `a second overflow skips the turn`() async throws {
        try await withStore { store, _ in
            try await Self.storeNotes(in: store)
            let run = BudgetRun(
                outcomes: [.failure(.contextSizeExceeded), .failure(.contextSizeExceeded)],
                seeds: [.topic("new bread"), .topic("the river")],
            )

            let (outcome, calls) = try await run.write(in: store)

            #expect(outcome == .skipped(.overflow))
            #expect(calls.count == 2)
        }
    }

    @Test
    func `an overflow with no post to halve skips at once`() async throws {
        try await withStore { store, _ in
            let run = BudgetRun(outcomes: [
                .failure(.contextSizeExceeded),
                .content(Self.akiSpeaks),
            ])

            let (outcome, calls) = try await run.write(in: store)

            #expect(outcome == .skipped(.overflow))
            #expect(calls.count == 1)
        }
    }

    @Test
    func `the halved posts carry over to the next seed after a refusal`() async throws {
        try await withStore { store, _ in
            try await Self.storeNotes(in: store)
            let run = BudgetRun(
                outcomes: [
                    .failure(.contextSizeExceeded),
                    .failure(.refused),
                    .content(Self.akiSpeaks),
                ],
                seeds: [.topic("new bread"), .topic("the river")],
            )

            let calls = try await run.calls(in: store)

            #expect(Self.notesCarried(by: calls).map(\.count) == [9, 4, 4])
            #expect(calls.last?.prompt.contains(#"the topic "the river""#) == true)
        }
    }
}
