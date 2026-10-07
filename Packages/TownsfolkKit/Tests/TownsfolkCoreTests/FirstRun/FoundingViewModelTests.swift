import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// S3 while founding runs (ux-flows S3; REQ-005, REQ-006): each line checked as #20's
/// founder reports its step, and the slow line after 60 s.
@MainActor
@Suite("FoundingViewModel, progress")
struct FoundingViewModelProgressTests {
    @Test
    func `each line is checked as the founder reports its step, and nothing else changes`(
    ) async throws {
        try await withStore { store, _ in
            let fake = FirstRunFixtures.heldFake(FoundingFixtures.happyPath)
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
            )
            #expect(FirstRunFixtures.lines(of: model).map(\.1) == [false, false, false])
            let running = Task { try await model.run() }

            // The town's call, then three residents' calls, then the first scene's.
            await fake.waitUntilHeld(count: 1)
            #expect(FirstRunFixtures.lines(of: model).map(\.1) == [false, false, false])
            fake.releaseHeld()
            await fake.waitUntilHeld(count: 1)
            #expect(FirstRunFixtures.lines(of: model).map(\.1) == [true, false, false])
            for _ in 1 ... 3 {
                fake.releaseHeld()
                await fake.waitUntilHeld(count: 1)
            }
            #expect(FirstRunFixtures.lines(of: model).map(\.1) == [true, true, false])
            #expect(model.phase == .founding)
            fake.releaseHeld()
            try await running.value

            #expect(FirstRunFixtures.lines(of: model).map(\.1) == [true, true, true])
            #expect(model.phase == .founded)
        }
    }

    @Test
    func `the words on S3 read as ux-guidelines writes them`() throws {
        let model = try FirstRunFixtures.idleFounding(FirstRunFixtures.tomo())
        #expect(model.heading.resolved(in: .english) == "Finding you a town…")
        #expect(FirstRunFixtures.lines(of: model).map(\.0) == [
            "Drawing the streets",
            "Meeting the neighbors",
            "Saying hello",
        ])
        #expect(model.steps.map(\.step) == [.town, .residents, .firstScene])
        #expect(model.slowNotice == nil)
        #expect(model.failureMessage == nil)
        #expect(model.tryAgainTitle.resolved(in: .english) == "Try Again")
    }

    @Test
    func `each step's symbol says whether it is done or not yet`() throws {
        let model = try FoundingViewModel(
            previewing: FirstRunFixtures.tomo(),
            finished: [.town],
            isSlow: false,
            phase: .founding,
        )
        #expect(model.steps.map { $0.status.resolved(in: .english) } == [
            "Done",
            "Not yet",
            "Not yet",
        ])
        #expect(model.steps.map(\.id) == [.town, .residents, .firstScene])
    }

    @Test
    func `after 60 s of founding the slow line appears under the steps`() async throws {
        try await withStore { store, _ in
            let fake = FirstRunFixtures.heldFake(FoundingFixtures.happyPath)
            let clock = EngineClock()
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
                clock: clock,
            )
            let running = Task { try await model.run() }
            await fake.waitUntilHeld(count: 1)
            await clock.waitForSleepers(count: 1)

            clock.advance(by: .seconds(59))
            #expect(model.slowNotice == nil)
            #expect(!model.isSlow)

            clock.advance(by: .seconds(1))
            await waitUntil { model.isSlow }
            #expect(
                model.slowNotice?.resolved(in: .english) == "This is taking longer than usual.",
            )
            #expect(model.phase == .founding)

            running.cancel()
            await #expect(throws: CancellationError.self) { try await running.value }
        }
    }

    @Test
    func `founding that ends before the wait stops waiting and never turns slow`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let clock = EngineClock()
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
                clock: clock,
            )

            try await model.run()

            #expect(model.phase == .founded)
            #expect(clock.sleeperCount == 0)
            clock.advance(by: .seconds(60))
            #expect(!model.isSlow)
            #expect(model.slowNotice == nil)
        }
    }

    @Test
    func `the slow line shows only while founding is still running`() throws {
        let tomo = try FirstRunFixtures.tomo()
        let slowAndFailed = FoundingViewModel(
            previewing: tomo,
            finished: [],
            isSlow: true,
            phase: .failed,
        )
        let slowAndFounding = FoundingViewModel(
            previewing: tomo,
            finished: [.town],
            isSlow: true,
            phase: .founding,
        )
        #expect(slowAndFailed.slowNotice == nil)
        #expect(slowAndFounding.slowNotice != nil)
    }
}

/// S3's endings (REQ-007, REQ-008, and the boundary on an unavailable model): a failure
/// with Try Again, a founded town announced, and the model going away reported apart.
@MainActor
@Suite("FoundingViewModel, endings")
struct FoundingViewModelEndingTests {
    private static let refusals = Array(
        repeating: FoundingFixtures.Answer.failure(.refused),
        count: 3,
    )

    @Test
    func `founding reports the new town and announces that you moved there`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
            )
            #expect(model.announcement == nil)

            try await model.run()

            #expect(model.phase == .founded)
            #expect(model.town?.name == "Maplewood")
            #expect(model.announcement?.resolved(in: .english) == "You moved to Maplewood.")
            #expect(model.failureMessage == nil)
        }
    }

    @Test
    func `three refusals show the failure, store nothing, and Try Again founds afresh`(
    ) async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(Self.refusals + FoundingFixtures.happyPath)
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
            )

            try await model.run()

            #expect(model.phase == .failed)
            #expect(
                model.failureMessage?
                    .resolved(in: .english) == "Couldn't find you a town this time.",
            )
            #expect(fake.calls.count == 3)
            #expect(model.announcement == nil)
            try await expectEmpty(store)

            let attempt = model.attempt
            model.tryAgainPressed()
            #expect(model.phase == .founding)
            #expect(model.attempt == attempt + 1)
            #expect(model.failureMessage == nil)
            #expect(model.steps.allSatisfy { !$0.isDone })

            try await model.run()

            #expect(model.phase == .founded)
            #expect(model.displayName.value == "Tomo")
            #expect(fake.prompts.last?.contains("You: Tomo") == true)
            #expect(try await store.town()?.name == "Maplewood")
        }
    }

    @Test
    func `pressing Try Again clears the steps and the slow line a failed run left`() throws {
        let model = try FoundingViewModel(
            previewing: FirstRunFixtures.tomo(),
            finished: [.town, .residents],
            isSlow: true,
            phase: .failed,
        )
        model.tryAgainPressed()
        #expect(model.phase == .founding)
        #expect(!model.isSlow)
        #expect(model.steps.allSatisfy { !$0.isDone })
    }

    @Test(arguments: [
        ModelAvailability.appleIntelligenceOff,
        .deviceNotEligible,
        .modelNotReady,
    ])
    func `an unavailable model is reported apart from a failure`(
        availability: ModelAvailability,
    ) async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            fake.availability = availability
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
            )

            try await model.run()

            #expect(model.phase == .unavailable(availability))
            #expect(model.failureMessage == nil)
            #expect(model.announcement == nil)
            try await expectEmpty(store)
        }
    }

    @Test
    func `founding can start again once the model is back`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            fake.availability = .modelNotReady
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
            )
            try await model.run()
            fake.availability = .available

            model.tryAgainPressed()
            try await model.run()

            #expect(model.phase == .founded)
        }
    }

    @Test(arguments: [FoundingViewModel.Phase.founding, .founded])
    func `pressing Try Again does nothing while founding runs or once it succeeded`(
        phase: FoundingViewModel.Phase,
    ) throws {
        let model = try FoundingViewModel(
            previewing: FirstRunFixtures.tomo(),
            finished: [.town],
            isSlow: false,
            phase: phase,
        )
        model.tryAgainPressed()
        #expect(model.phase == phase)
        #expect(model.attempt == 0)
        #expect(model.steps.first?.isDone == true)
    }
}

/// Founding runs once at a time, as #20's founder requires, and a cancelled run leaves
/// the screen as it was.
@MainActor
@Suite("FoundingViewModel, running")
struct FoundingViewModelTests {
    @Test
    func `a second run while one is founding returns at once without founding again`(
    ) async throws {
        try await withStore { store, _ in
            let fake = FirstRunFixtures.heldFake(FoundingFixtures.happyPath)
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
            )
            let running = Task { try await model.run() }
            await fake.waitUntilHeld(count: 1)

            try await model.run()

            #expect(fake.calls.count == 1)
            running.cancel()
            await #expect(throws: CancellationError.self) { try await running.value }
        }
    }

    @Test
    func `a founded screen does not found again`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
            )
            try await model.run()
            let calls = fake.calls.count

            try await model.run()

            #expect(fake.calls.count == calls)
            #expect(model.phase == .founded)
        }
    }

    @Test
    func `a cancelled run stores nothing and leaves the steps it had checked`() async throws {
        try await withStore { store, _ in
            let fake = FirstRunFixtures.heldFake(FoundingFixtures.happyPath)
            let model = try FirstRunFixtures.founding(
                fake,
                store: store,
                name: FirstRunFixtures.tomo(),
            )
            let running = Task { try await model.run() }
            await fake.waitUntilHeld(count: 1)
            fake.releaseHeld()
            await fake.waitUntilHeld(count: 1)

            running.cancel()

            await #expect(throws: CancellationError.self) { try await running.value }
            #expect(model.phase == .founding)
            #expect(FirstRunFixtures.lines(of: model).map(\.1) == [true, false, false])
            try await expectEmpty(store)
        }
    }

    @Test
    func `a preview screen never founds`() async throws {
        let model = try FirstRunFixtures.idleFounding(FirstRunFixtures.tomo())
        try await model.run()
        #expect(model.phase == .founding)
        #expect(model.steps.allSatisfy { !$0.isDone })
    }
}
