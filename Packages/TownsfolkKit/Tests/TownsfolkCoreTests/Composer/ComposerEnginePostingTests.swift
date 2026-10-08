import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

@MainActor
@Suite("Composer atomic engine posting")
struct ComposerEnginePostingTests {
    @Test
    func `held scene does not delay posting or change captured speed`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.speed = .fast
        setup.holdsResponses = true
        setup.outcomes = [.content(WritingFixtures.mikaSpeaks)]
        try await withEngine(setup) { harness in
            let engine = harness.engine
            let scene = Task { try await engine.step() }
            await harness.model.waitUntilHeld(count: 1)
            let settings = harness.settings
            let write: ComposerViewModel.Write = { post throws(TownStoreError) in
                let speed = settings.speed
                try await engine.submitYourPost(post, speed: speed)
            }
            let composer = ComposerViewModel(write: write) { EngineFixtures.start }
            composer.textChanged(to: "Fresh bread?")
            await composer.returnPressed()
            #expect(composer.text.isEmpty)
            #expect(harness.model.calls.count == 1)
            let responses = try #require(await harness.store.schedule()).pendingResponses
            #expect(responses.map(\.dueAt) == [EngineFixtures.time("10:07:00")])
            settings.speed = .slow
            harness.model.releaseHeld()
            _ = try await scene.value
            let reopened = try TownStore(directory: harness.directory.town)
            #expect(try await reopened.schedule()?.pendingResponses == responses)
        }
    }

    @Test
    func `failed pruning rolls back post and responses and preserves input`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        try await withEngine(setup) { harness in
            for second in 0 ..< 3 {
                let post = try EngineResponseFixtures
                    .post(at: EngineFixtures.start.addingTimeInterval(Double(second)))
                try await harness.engine.submitYourPost(post, speed: .normal)
            }
            let raw = try harness.directory.raw()
            try raw.execute("""
            CREATE TRIGGER refuse_prune AFTER DELETE ON pending_responses
            BEGIN SELECT RAISE(ABORT, 'planted by the test'); END
            """)
            let before = try raw.snapshot()
            let changes = await harness.store.changes()
            let engine = harness.engine
            let write: ComposerViewModel.Write = { post throws(TownStoreError) in
                try await engine.submitYourPost(post, speed: .normal)
            }
            let composer = ComposerViewModel(write: write) {
                EngineFixtures.start.addingTimeInterval(3)
            }
            composer.textChanged(to: "Keep this input.")
            await composer.returnPressed()
            #expect(composer.text == "Keep this input.")
            #expect(try raw.snapshot() == before)
            try await harness.store.setLastRan(EngineFixtures.start)
            #expect(await firstChange(changes) == .lastRanChanged)
        }
    }

    @Test
    func `concurrent submits keep newest three schedules`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        try await withEngine(setup) { harness in
            let posts = try (0 ..< 8).map { second in
                try EngineResponseFixtures
                    .post(at: EngineFixtures.start.addingTimeInterval(Double(second)))
            }
            let engine = harness.engine
            try await withThrowingTaskGroup(of: Void.self) { group in
                for post in posts {
                    group.addTask {
                        try await engine.submitYourPost(post, speed: .normal)
                    }
                }
                try await group.waitForAll()
            }
            #expect(try await ComposerFixtures.yourPosts(in: harness.store).count == 8)
            #expect(try await harness.store.schedule()?.pendingResponses
                .map(\.post) == Array(posts.suffix(3)).map(\.id))
        }
    }

    @Test
    func `injected writer honors custom tuning`() {
        var tuning = Tuning.default
        tuning.yourPost.yourPostLength = 1 ... 5
        let write: ComposerViewModel.Write = { _ in
            // This preview does not submit anything.
        }
        let composer = ComposerViewModel(write: write, tuning: tuning) { EngineFixtures.start }
        composer.textChanged(to: "123456")
        #expect(!composer.canPost)
        composer.textChanged(to: "12345")
        #expect(composer.canPost)
    }

    @Test
    func `resident post is rejected without writing`() async throws {
        let setup = try EngineSetup.mikaAlone()
        try await withEngine(setup) { harness in
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let residentPost = try ResidentPostDraft(
                author: harness.residents[0].id,
                time: EngineFixtures.start,
            ).make()
            await #expect(throws: TownStoreError.rejectedRow(.notAllowed(.origin))) {
                try await harness.engine.submitYourPost(residentPost, speed: .normal)
            }
            #expect(try raw.snapshot() == before)
            #expect(harness.model.calls.isEmpty)
        }
    }

    @Test
    func `canceled posting preserves input and store`() async throws {
        let setup = try EngineSetup.mikaAlone()
        try await withEngine(setup) { harness in
            let raw = try harness.directory.raw()
            let before = try raw.snapshot()
            let engine = harness.engine
            let write: ComposerViewModel.Write = { post throws(TownStoreError) in
                try await engine.submitYourPost(post, speed: .normal)
            }
            let composer = ComposerViewModel(write: write) { EngineFixtures.start }
            composer.textChanged(to: "Keep this input.")
            let posting = Task { await composer.returnPressed() }
            posting.cancel()
            await posting.value
            #expect(composer.text == "Keep this input.")
            #expect(try raw.snapshot() == before)
            #expect(harness.model.calls.isEmpty)
        }
    }
}
