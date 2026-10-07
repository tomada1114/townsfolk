import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// A failed step leaves nothing behind (REQ-009; `docs/architecture.md` › Quality
/// targets), and a cancelled one stops without a partial scene (REQ-012).
@Suite("Town engine failures and cancellation")
struct EngineFailureTests {
    /// SQLITE_CONSTRAINT_TRIGGER: the planted trigger refused an insert.
    static let refusedByTrigger = TownStoreError.statementFailed(code: 1_811)

    /// Refuses every post that replies to another, so a two-post scene fails at its
    /// second insert, after the first went in.
    static let refuseReplies = """
    CREATE TRIGGER refuse_replies BEFORE INSERT ON posts
    WHEN NEW.reply_target_id IS NOT NULL
    BEGIN SELECT RAISE(ABORT, 'planted by the test'); END
    """

    /// Mika alone with 120 posts already stored, answering two-post scenes.
    static func townOf120Posts() throws -> EngineSetup {
        var setup = try EngineSetup.mikaAlone()
        let mika = setup.residents[0].id
        setup.priorPosts = try (0 ..< 120).map { second in
            try ResidentPostDraft(
                author: mika,
                time: StoreFixtures.morning.addingTimeInterval(TimeInterval(second)),
            ).make()
        }
        let scene = FakeLanguageModelProvider.Outcome.content(EngineFixtures.scene(
            by: "Mika",
            ["Fresh bread.", "Come early."],
            tags: ["bread"],
        ))
        setup.outcomes = [scene, scene]
        return setup
    }

    @Test
    func `a scene whose second post fails to store leaves the store as it was`() async throws {
        try await withEngine(Self.townOf120Posts()) { harness in
            let raw = try harness.directory.raw()
            try raw.execute(Self.refuseReplies)
            let before = try raw.snapshot()

            let outcome = try await harness.engine.step()

            #expect(outcome == .failed(Self.refusedByTrigger))
            #expect(try raw.snapshot() == before)
            #expect(try raw.count("posts") == 120)
            #expect(try await harness.storedDue() == EngineFixtures.time("10:06:00"))
        }
    }

    @Test
    func `run waits one drawn interval after a failed step, then tries again`() async throws {
        try await withEngine(Self.townOf120Posts()) { harness in
            let raw = try harness.directory.raw()
            try raw.execute(Self.refuseReplies)
            let engine = harness.engine
            let running = Task { try await engine.run() }

            await harness.clock.waitForSleepers(count: 1)
            #expect(harness.clock.nextDeadline == .milliseconds(402_654))
            #expect(try raw.count("posts") == 120)
            try raw.execute("DROP TRIGGER refuse_replies")
            harness.clock.advanceToNextDeadline()
            await harness.clock.waitForSleepers(count: 1)
            running.cancel()
            _ = await running.result

            #expect(try raw.count("posts") == 122)
            #expect(harness.model.calls.count == 2)
        }
    }

    @Test
    func `a store that cannot be read fails the step without a call`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            try await harness.store.deleteEverything()

            #expect(try await harness.engine.step() == .failed(.closed))
            #expect(await harness.engine.speedChanged() == nil)
            #expect(harness.model.calls.isEmpty)
        }
    }

    @Test
    func `a step cancelled while writing stores nothing and throws`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        setup.holdsResponses = true
        try await withEngine(setup) { harness in
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let engine = harness.engine
            let stepping = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)

            stepping.cancel()

            await #expect(throws: CancellationError.self) {
                try await stepping.value
            }
            #expect(try raw.snapshot() == before)
            harness.model.availability = .modelNotReady
            #expect(try await engine.step() == .modelUnavailable)
        }
    }

    @Test
    func `run cancelled while waiting stops and throws`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.due = EngineFixtures.time("10:12:00")
        try await withEngine(setup) { harness in
            let engine = harness.engine
            let running = Task { try await engine.run() }
            await harness.clock.waitForSleepers(count: 1)
            #expect(harness.clock.nextDeadline == .seconds(360))

            running.cancel()

            await #expect(throws: CancellationError.self) {
                try await running.value
            }
            #expect(harness.clock.sleeperCount == 0)
            #expect(harness.model.calls.isEmpty)
        }
    }
}
