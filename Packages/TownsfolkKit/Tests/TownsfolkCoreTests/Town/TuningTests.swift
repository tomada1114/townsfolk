import Testing
import TownsfolkCore

/// Pins every starting value in `Tuning.default` to the literal in issue #5's table,
/// one expectation per entry, so changing a † value is a deliberate edit here too.
@Suite("Tuning")
struct TuningTests {
    let tuning = Tuning.default

    @Test
    func `founding starts at the requirements' values`() {
        #expect(tuning.founding.displayNameLength == 1 ... 20)
        #expect(tuning.founding.townNameMaxLength == 30)
        #expect(tuning.founding.placeCount == 3 ... 5)
        #expect(tuning.founding.foundingResidentCount == 3)
        #expect(tuning.founding.foundingAttempts == 3)
    }

    @Test
    func `the timeline starts at the requirements' values`() {
        #expect(tuning.timeline.revealSpacing == 0.10 ... 0.30)
        #expect(tuning.timeline.residentPostMaxLength == 280)
        #expect(tuning.timeline.statusLineLineLimit == 1)
    }

    @Test
    func `the pace starts at the requirements' values`() {
        #expect(
            tuning.pace.sceneInterval
                == PerSpeed(fast: .seconds(60), normal: .seconds(360), slow: .seconds(1_800)),
        )
        #expect(tuning.pace.sceneIntervalJitter == 0.5)
    }

    @Test
    func `your post starts at the requirements' values`() {
        let yourPost = tuning.yourPost
        #expect(yourPost.yourPostLength == 1 ... 140)
        #expect(yourPost.firstResponseDelay == .seconds(120) ... .seconds(600))
        #expect(yourPost.responseDelayScale == PerSpeed(fast: 0.5, normal: 1, slow: 2))
        #expect(yourPost.responseSceneCount == 1 ... 3)
        #expect(yourPost.responseSceneWeights == [3, 2, 1])
        #expect(yourPost.responseSpan == .seconds(3_600))
        #expect(yourPost.postSeedLifetime == .seconds(86_400))
        #expect(yourPost.postSeedChance == 0.05)
        #expect(yourPost.repliedResidentSpeaksFirstChance == 0.70)
        #expect(yourPost.maxPostsAwaitingResponses == 3)
    }

    @Test
    func `events start at the requirements' values`() {
        #expect(tuning.events.eventInterval == .seconds(10_800))
        #expect(tuning.events.eventDuration == .seconds(3_600) ... .seconds(43_200))
        #expect(tuning.events.maxOngoingEvents == 2)
    }

    @Test
    func `residents start at the requirements' values`() {
        #expect(tuning.residents.population == 3 ... 10)
        #expect(tuning.residents.moveInterval == .seconds(86_400) ... .seconds(172_800))
        #expect(tuning.residents.newcomerFromNameChance == 0.5)
    }

    @Test
    func `catch-up starts at the requirements' values`() {
        #expect(tuning.catchUp.catchUpIntervalsPerScene == 4)
        #expect(tuning.catchUp.catchUpMaxScenes == 5)
        #expect(tuning.catchUp.catchUpNewsPause == .seconds(7_200))
        #expect(tuning.catchUp.catchUpMaxEvents == 1)
        #expect(tuning.catchUp.catchUpMaxMoves == 1)
    }

    @Test
    func `generation starts at the requirements' values`() {
        #expect(tuning.generation.recentContextWindow == .seconds(86_400))
        #expect(tuning.generation.refusalRetriesPerTurn == 2)
        #expect(tuning.generation.refusalsBeforeLeftOut == 3)
        #expect(tuning.generation.outputTokenReserve == 1_024)
    }

    @Test
    func `a per-speed value reads the entry for each speed`() {
        let intervals = tuning.pace.sceneInterval
        #expect(intervals[.slow] == .seconds(1_800))
        #expect(intervals[.normal] == .seconds(360))
        #expect(intervals[.fast] == .seconds(60))
    }

    @Test
    func `a changed copy differs from the default and leaves it untouched`() {
        var custom = Tuning.default
        custom.founding.displayNameLength = 2 ... 4
        #expect(custom != Tuning.default)
        #expect(Tuning.default.founding.displayNameLength == 1 ... 20)
    }
}
