import Foundation
import Testing
import TownsfolkCore

@Suite("Response schedule repair")
struct EngineResponseRepairTests {
    private static func reopenedEngine(_ harness: EngineHarness) throws -> TownEngine {
        let reopened = try TownStore(directory: harness.directory.town)
        return try TownEngine(
            parts: TownEngine.Parts(
                store: reopened,
                writer: SceneWriter(model: harness.model, store: reopened),
                settings: SettingsStore(
                    defaults: #require(UserDefaults(suiteName: "Repair-\(UUID().uuidString)")),
                ),
                seedTables: SeedTables.load(),
                model: harness.model,
            ),
            world: TownEngine.World(
                thermalState: { .nominal },
                now: { EngineFixtures.start },
                generator: RepeatingGenerator(value: 0),
            ),
        )
    }

    @Test(arguments: [2, 3, 4])
    func `all newest unscheduled posts recover`(count: Int) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.availability = .modelNotReady
        try await withEngine(setup) { harness in
            var posts: [Post] = []
            for second in 0 ..< count {
                let post = try EngineResponseFixtures
                    .post(at: EngineFixtures.start.addingTimeInterval(Double(second)))
                posts.append(post)
                try await harness.store.storeYourPost(post)
            }
            _ = try await harness.engine.step()
            let expected = Array(posts.suffix(3)).map(\.id)
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.post) == expected)
            _ = try await harness.engine.step()
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.post) == expected)
        }
    }

    @Test(arguments: [false, true])
    func `newest filtered posts do not resurrect older history`(excluded: Bool) async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.generator = RepeatingGenerator(value: 0)
        setup.availability = .modelNotReady
        try await withEngine(setup) { harness in
            var posts: [Post] = []
            for second in 0 ..< 4 {
                let post = try EngineResponseFixtures
                    .post(at: EngineFixtures.start.addingTimeInterval(Double(second)))
                posts.append(post)
                try await harness.store.storeYourPost(post)
            }
            let newest = try #require(posts.last)
            if excluded {
                try await harness.store.excludePost(newest.id)
            } else {
                let answer = try EngineResponseFixtures.answered(
                    newest,
                    by: harness.residents[0].id,
                )
                try await harness.store.storeScene(.init(posts: [answer]))
            }
            let engine = try Self.reopenedEngine(harness)
            _ = try await engine.step()
            #expect(try await harness.store.schedule()?.pendingResponses.map(\.post) == [
                posts[1].id,
                posts[2].id,
            ])
        }
    }
}
