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
    var tuning = Tuning.default

    func write(in store: TownStore) async throws -> (SceneOutcome, [Call]) {
        let cast = try WritingCast()
        let fake = WritingFixtures.fake(outcomes, contextSize: contextSize)
        let writer = SceneWriter(model: fake, store: store, tuning: tuning)
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
    static let numberedPostCount = 1_000

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

    /// Stores numbered posts at one-second intervals, all inside the recent window.
    static func storeNumberedPosts(in directory: TownDirectory) throws {
        let firstPostTime = Int64(WritingFixtures.now.timeIntervalSince1970 * 1_000)
            - Int64(numberedPostCount * 1_000)
        let database = try directory.raw()
        try database.execute("""
        WITH RECURSIVE sequence(number) AS (
            SELECT 1
            UNION ALL SELECT number + 1 FROM sequence WHERE number < \(numberedPostCount)
        )
        INSERT INTO posts (id, author_resident_id, text, happened_at, reply_target_id,
            origin, scene_id)
        SELECT printf('00000000-0000-0000-0000-%012d', number), NULL,
            printf('Note %04d.', number), \(firstPostTime) + (number * 1_000),
            NULL, NULL, NULL
        FROM sequence
        """)
    }

    static func note(_ index: Int) -> String {
        "Note \(String(format: "%04d", index))."
    }

    /// Makes one numbered post fail the store's normal text validation when read.
    static func corruptPost(_ index: Int, in directory: TownDirectory) throws {
        let database = try directory.raw()
        try database.execute("UPDATE posts SET text = '   ' WHERE text = '\(note(index))'")
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

    @Test(arguments: [64, 8])
    func `the bounded read carries only the newest configured posts`(limit: Int) async throws {
        try await withStore { store, directory in
            try Self.storeNumberedPosts(in: directory)
            try Self.corruptPost(Self.numberedPostCount - limit, in: directory)
            var tuning = Tuning.default
            if limit != 64 {
                tuning.generation.maxRecentPosts = limit
            }

            let (outcome, calls) = try await BudgetRun(tuning: tuning).write(in: store)

            guard case .written = outcome else {
                Issue.record("expected the capped recent posts to write a scene, got \(outcome)")
                return
            }
            let call = try #require(calls.first)
            let carried = (1 ... Self.numberedPostCount).map(Self.note).filter { note in
                call.prompt.contains("\"\(note)\"")
            }
            let expected = ((Self.numberedPostCount - limit + 1) ... Self.numberedPostCount)
                .map(Self.note)
            #expect(calls.count == 1)
            #expect(carried == expected)
        }
    }

    @Test
    func `a corrupt post inside the read cap still fails the store read`() async throws {
        try await withStore { store, directory in
            try Self.storeNumberedPosts(in: directory)
            try Self.corruptPost(Self.numberedPostCount, in: directory)
            var tuning = Tuning.default
            tuning.generation.maxRecentPosts = 8
            let cast = try WritingCast()
            let fake = WritingFixtures.fake([.content(Self.akiSpeaks)])
            let writer = SceneWriter(model: fake, store: store, tuning: tuning)
            let request = try cast.request(speakers: [cast.aki], seeds: [.topic("new bread")])

            let outcome = try await writer.write(request, at: WritingFixtures.now)

            #expect(
                outcome == .skipped(.storeReadFailed(.rejectedRow(.empty(.postText)))),
            )
            #expect(fake.calls.isEmpty)
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
