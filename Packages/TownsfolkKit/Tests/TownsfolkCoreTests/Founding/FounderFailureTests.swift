import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// Failed attempts (REQ-007, REQ-008): each is retried with new seeds, keeping the steps
/// already done, and they add up across steps to a failure that stores nothing.
@Suite("Founder failures")
struct FounderFailureTests {
    @Test
    func `three refused town calls end in failure, and a new call starts a fresh count`(
    ) async throws {
        try await withStore { store, _ in
            let refusals = Array(repeating: FoundingFixtures.Answer.failure(.refused), count: 3)
            let fake = FoundingFixtures.fake(refusals + FoundingFixtures.happyPath)
            let founder = try founder(fake, store: store)
            let log = ProgressLog()

            #expect(try await found(with: founder, log: log) == .failed)

            #expect(fake.calls.count == 3)
            #expect(log.reported.isEmpty)
            try await expectEmpty(store)

            #expect(try await found(with: founder) == .founded)
            #expect(fake.calls.count == 8)
        }
    }

    @Test
    func `failed attempts in different steps add up`() async throws {
        try await withStore { store, _ in
            let fake = FoundingFixtures.fake([
                .failure(.other),
                .town(FoundingFixtures.maplewood),
                .resident(FoundingFixtures.mika),
                .failure(.contextSizeExceeded),
                .resident(FoundingFixtures.jun),
                .resident(FoundingFixtures.sora),
                .scene([DraftPost(speaker: "Nobody", text: "Hi.")]),
                .scene(FoundingFixtures.welcome),
            ])
            let log = ProgressLog()

            #expect(try await found(with: founder(fake, store: store), log: log) == .failed)

            #expect(fake.calls.count == 7)
            #expect(log.reported == [.town, .residents])
            try await expectEmpty(store)
        }
    }

    @Test
    func `two failed attempts and then a success found the town`() async throws {
        try await withStore { store, _ in
            let failures: [FoundingFixtures.Answer] = [.failure(.refused), .failure(.other)]
            let fake = FoundingFixtures.fake(failures + FoundingFixtures.happyPath)

            let outcome = try await found(with: founder(fake, store: store))

            #expect(outcome == .founded)

            #expect(fake.calls.count == 7)
        }
    }

    @Test
    func `a failed resident keeps the town and the residents invented so far`() async throws {
        try await withStore { store, _ in
            var answers = FoundingFixtures.happyPath
            answers.insert(.failure(.refused), at: 2)
            let fake = FoundingFixtures.fake(answers)

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            let prompts = fake.prompts
            try #require(prompts.count == 6)
            #expect(prompts.filter { $0.hasPrefix("Invent the town.") }.count == 1)
            #expect(prompts.filter { $0.contains("Occupation: baker") }.count == 1)
            #expect(prompts[3].contains("Names already taken: Mika"))
            #expect(prompts[3].contains("Occupation: florist"))
        }
    }

    @Test
    func `a skipped first scene is retried with other profile seeds`() async throws {
        try await withStore { store, _ in
            var answers = FoundingFixtures.happyPath
            answers.insert(.scene([DraftPost(speaker: "Nobody", text: "Hi.")]), at: 4)
            let fake = FoundingFixtures.fake(answers)

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            let prompts = fake.prompts
            try #require(prompts.count == 6)
            #expect(prompts[4].contains("Seed: Mika's hobby: fishing."))
            #expect(prompts[5].contains("Seed: Mika's worry: the oven cooling too early."))
            #expect(prompts.filter { $0.hasPrefix("Invent the town.") }.count == 1)
        }
    }

    @Test
    func `a first scene refused on every seed is one failed attempt`() async throws {
        try await withStore { store, _ in
            var answers = FoundingFixtures.happyPath
            answers.insert(contentsOf: Array(repeating: .failure(.refused), count: 3), at: 4)
            let fake = FoundingFixtures.fake(answers)

            #expect(try await found(with: founder(fake, store: store)) == .founded)

            let prompts = fake.prompts
            try #require(prompts.count == 8)
            #expect(prompts[4].contains("Seed: Mika's hobby: fishing."))
            #expect(prompts[5].contains("Seed: Mika's occupation: baker."))
            #expect(prompts[6].contains("Seed: Mika's personality: cheerful."))
            #expect(prompts[7].contains("Seed: Mika's worry:"))
        }
    }
}
