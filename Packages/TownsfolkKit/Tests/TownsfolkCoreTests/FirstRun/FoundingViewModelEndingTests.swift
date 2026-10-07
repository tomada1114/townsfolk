import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

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

            // S3 stays while the announcement waits to be posted: `.founded`, the signal
            // the owner leaves S3 on, comes only once the view posted it.
            #expect(model.phase == .arrived)
            #expect(model.town?.name == "Maplewood")
            #expect(model.announcement?.resolved(in: .english) == "You moved to Maplewood.")
            #expect(model.steps.map(\.isDone) == [true, true, true])
            #expect(model.failureMessage == nil)
            #expect(model.slowNotice == nil)

            model.announcementPosted()

            #expect(model.phase == .founded)
            #expect(model.town?.name == "Maplewood")
        }
    }

    @Test(arguments: [
        FoundingViewModel.Phase.founding,
        .failed,
        .unavailable(.modelNotReady),
        .founded,
    ])
    func `an announcement posted before the town arrived changes nothing`(
        phase: FoundingViewModel.Phase,
    ) throws {
        let model = try FoundingViewModel(
            previewing: FirstRunFixtures.tomo(),
            finished: [],
            isSlow: false,
            phase: phase,
        )
        model.announcementPosted()
        #expect(model.phase == phase)
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

            #expect(model.phase == .arrived)
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

            #expect(model.phase == .arrived)
        }
    }

    @Test(arguments: [FoundingViewModel.Phase.founding, .arrived, .founded])
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
