import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// A speed change applies from the next scene (REQ-010, requirements.md:210): the pending
/// due time is measured again from the same last post with the same jitter draw, 0.8399…
/// in a two-post scene seeded 42, and `run()` re-arms its wait.
@Suite("Town engine speed changes")
struct EngineSpeedTests {
    static func twoPostScene() throws -> EngineSetup {
        var setup = try EngineSetup.mikaAlone()
        let scene = EngineFixtures.scene(
            by: "Mika",
            ["Fresh bread.", "Come early."],
            tags: ["bread"],
        )
        setup.outcomes = [.content(scene)]
        return setup
    }

    @Test(arguments: [
        (Speed.fast, "10:08:24.041"),
        (.normal, "10:12:36.020"),
        (.slow, "10:32:45.521"),
    ])
    func `the pending due time is measured again from the last post`(
        speed: Speed,
        expected: String,
    ) async throws {
        try await withEngine(Self.twoPostScene()) { harness in
            _ = try await harness.engine.step()
            harness.settings.speed = speed

            let due = await harness.engine.speedChanged()

            #expect(due == EngineFixtures.time(expected))
            #expect(try await harness.storedDue() == EngineFixtures.time(expected))
            let posts = try await harness.storedPosts()
            #expect(posts.map(\.happenedAt) == [
                EngineFixtures.time("10:07:33.645"),
                EngineFixtures.time("10:06:00"),
            ])
        }
    }

    @Test
    func `before any turn a speed change draws afresh from now`() async throws {
        var setup = try EngineSetup.mikaAlone()
        setup.due = EngineFixtures.time("10:12:00")
        try await withEngine(setup) { harness in
            harness.settings.speed = .fast

            let due = await harness.engine.speedChanged()

            let stored = try await harness.storedDue()
            #expect(due == EngineFixtures.time("10:07:14.494"))
            #expect(stored == EngineFixtures.time("10:07:14.494"))
        }
    }

    @Test
    func `a speed change re-arms the wait run is in`() async throws {
        try await withEngine(Self.twoPostScene()) { harness in
            let engine = harness.engine
            let running = Task { try await engine.run() }
            await harness.clock.waitForSleepers(count: 1)
            #expect(harness.clock.nextDeadline == .milliseconds(396_020))

            harness.settings.speed = .fast
            await engine.speedChanged()
            await harness.clock.waitForSleepers(count: 1)

            #expect(harness.clock.nextDeadline == .milliseconds(144_041))
            running.cancel()
            _ = await running.result
        }
    }
}
