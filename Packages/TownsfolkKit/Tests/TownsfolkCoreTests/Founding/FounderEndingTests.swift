import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Founding that ends without a failed attempt being the reason (REQ-008–REQ-010): an
/// unavailable model ends it with its reason, cancellation propagates, a failed
/// transaction or unusable seed tables fail it — and the store keeps nothing of it.
@Suite("Founder endings")
struct FounderEndingTests {
    @Test(arguments: [
        ModelAvailability.appleIntelligenceOff,
        .deviceNotEligible,
        .modelNotReady,
    ])
    func `an unavailable model ends founding with its reason, without a call`(
        availability: ModelAvailability,
    ) async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            fake.availability = availability
            let log = ProgressLog()

            let outcome = try await found(with: founder(fake, store: store), log: log)

            #expect(outcome == .unavailable(availability))
            #expect(fake.calls.isEmpty)
            #expect(log.reported.isEmpty)
            try await expectEmpty(store)
        }
    }

    @Test(arguments: [(0, 1, [FoundingProgress]()), (2, 3, [.town]), (4, 5, [.town, .residents])])
    func `a call finding the model unavailable ends founding, not as a failed attempt`(
        failing: Int,
        calls: Int,
        reported: [FoundingProgress],
    ) async throws {
        try await withStore { store, _ in
            var answers = FoundingFixtures.happyPath
            answers.insert(.failure(.unavailable), at: failing)
            let fake = FoundingFixtures.fake(answers)
            let log = ProgressLog()

            let outcome = try await found(with: founder(fake, store: store), log: log)

            // The port still answers available, so the model is taken to be on its way
            // back.
            #expect(outcome == .unavailable(.modelNotReady))
            #expect(fake.calls.count == calls)
            #expect(log.reported == reported)
            try await expectEmpty(store)
        }
    }

    @Test
    func `the model going away mid-call ends founding with the reason the port then gives`(
    ) async throws {
        try await withStore { store, _ in
            let fake = ModelFixtures.heldFake(outcomes: [.failure(.unavailable)])
            let founder = try founder(fake, store: store)
            let task = Task {
                try await found(with: founder)
            }

            await fake.waitUntilHeld(count: 1)
            fake.availability = .appleIntelligenceOff
            fake.releaseHeld()

            #expect(try await task.value == .unavailable(.appleIntelligenceOff))
            #expect(fake.calls.count == 1)
            try await expectEmpty(store)
        }
    }

    @Test
    func `cancelling while the first scene is written propagates and stores nothing`(
    ) async throws {
        try await withStore { store, _ in
            let fake = ModelFixtures.heldFake(
                outcomes: FoundingFixtures.outcomes(FoundingFixtures.happyPath),
            )
            let founder = try founder(fake, store: store)
            let log = ProgressLog()
            let task = Task {
                try await found(with: founder, log: log)
            }
            for _ in 1 ... 4 {
                await fake.waitUntilHeld(count: 1)
                fake.releaseHeld()
            }

            await fake.waitUntilHeld(count: 1)
            task.cancel()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
            #expect(fake.calls.count == 5)
            #expect(log.reported == [.town, .residents])
            try await expectEmpty(store)
        }
    }

    @Test
    func `cancelling once the first scene is written, before the store commits, stores nothing`(
    ) async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let founder = try founder(fake, store: store)
            let task = Task {
                try await founder.found(displayName: DisplayName("Tomo")) { step in
                    // The last thing before the write: the store must still refuse it.
                    if step == .firstScene {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            }

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
            #expect(fake.calls.count == 5)
            try await expectEmpty(store)
        }
    }

    @Test
    func `a task cancelled before founding starts makes no call`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)
            let founder = try founder(fake, store: store)
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await found(with: founder)
            }

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
            #expect(fake.calls.isEmpty)
            try await expectEmpty(store)
        }
    }

    @Test
    func `a failed transaction ends in failure and keeps nothing`() async throws {
        try await withTownDirectory { directory in
            let store = try TownStore(directory: directory.town)
            let fake = ModelFixtures.heldFake(
                outcomes: FoundingFixtures.outcomes(FoundingFixtures.happyPath),
            )
            let founder = try founder(fake, store: store)
            let log = ProgressLog()
            let task = Task {
                try await found(with: founder, log: log)
            }
            for _ in 1 ... 4 {
                await fake.waitUntilHeld(count: 1)
                fake.releaseHeld()
            }
            await fake.waitUntilHeld(count: 1)
            // Moving away mid-founding closes the store, so the final write cannot commit.
            try await store.deleteEverything()
            fake.releaseHeld()

            #expect(try await task.value == .failed)
            #expect(log.reported == [.town, .residents, .firstScene])
            try await expectEmpty(TownStore(directory: directory.town))
        }
    }

    @Test
    func `a town already stored is refused at the transaction and left as it was`() async throws {
        try await withFoundedStore { store, existing, _ in
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)

            #expect(try await found(with: founder(fake, store: store)) == .failed)

            let town = try await store.town()
            let names = try await store.residents().map(\.name)
            #expect(town == existing.town)
            #expect(names.sorted() == ["Aki", "Mio", "Ren"])
        }
    }

    @Test(arguments: [
        (["baker"], ["cheerful"], ["young adult"], ["fishing", "chess"]),
        ([], ["cheerful"], ["young adult"], ["fishing"]),
    ])
    func `seed tables that cannot seat three different residents fail without a call`(
        occupations: [String],
        personalities: [String],
        lifeStages: [String],
        hobbies: [String],
    ) async throws {
        try await withStore { store, _ in
            let tables = try FoundingFixtures.tables(
                occupations: occupations,
                personalities: personalities,
                lifeStages: lifeStages,
                hobbies: hobbies,
            )
            let fake = FoundingFixtures.fake(FoundingFixtures.happyPath)

            let founder = founder(
                fake,
                store: store,
                generator: FoundingFixtures.FirstChoice(),
                tables: tables,
            )

            let outcome = try await found(with: founder)

            #expect(outcome == .failed)
            #expect(fake.calls.isEmpty)
            try await expectEmpty(store)
        }
    }

    @Test
    func `an outcome carries nothing the model wrote`() async throws {
        try await withStore { store, _ in
            let sentinel = ModelFixtures.sentinel
            let draft = TownDraft(name: sentinel, setting: sentinel, places: [sentinel])
            let fake = FoundingFixtures.fake(Array(repeating: .town(draft), count: 3))

            let outcome = try await found(with: founder(fake, store: store))

            #expect(outcome == .failed)
            #expect(!String(describing: outcome).contains(sentinel))
        }
    }
}
