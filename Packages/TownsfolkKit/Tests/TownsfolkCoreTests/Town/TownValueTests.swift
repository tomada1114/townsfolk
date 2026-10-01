import Foundation
import Testing
import TownsfolkCore

/// What every Town value shares: the language and speed raw values the settings keys
/// store (ADR-0004), the typed ids, the schedule, and an error that never repeats the
/// text it rejected.
@Suite("Town values")
struct TownValueTests {
    // MARK: - TownLanguage and Speed

    @Test
    func `languages carry the settings raw values, English first and by default`() {
        #expect(TownLanguage.allCases == [.english, .japanese])
        #expect(TownLanguage.english.rawValue == "en")
        #expect(TownLanguage.japanese.rawValue == "ja")
        #expect(TownLanguage(rawValue: "ja") == .japanese)
        #expect(TownLanguage(rawValue: "de") == nil)
        #expect(TownLanguage.default == .english)
    }

    @Test
    func `speeds carry the settings raw values, Normal by default`() {
        #expect(Speed.allCases == [.fast, .normal, .slow])
        #expect(Speed.slow.rawValue == "slow")
        #expect(Speed.normal.rawValue == "normal")
        #expect(Speed.fast.rawValue == "fast")
        #expect(Speed(rawValue: "fast") == .fast)
        #expect(Speed(rawValue: "Fast") == nil)
        #expect(Speed.default == .normal)
    }

    // MARK: - Ids

    @Test
    func `an id is its UUID`() throws {
        let uuid = try #require(UUID(uuidString: "6F1C2B4E-2F5A-4C3B-9E1D-7A8B9C0D1E2F"))
        let post = Post.ID(rawValue: uuid)
        let samePost = Post.ID(rawValue: uuid)
        #expect(post == samePost)
        #expect(post.rawValue == uuid)
        let scene = SceneID(rawValue: uuid)
        let sameScene = SceneID(rawValue: uuid)
        #expect(scene == sameScene)
        #expect(scene.rawValue == uuid)
    }

    @Test
    func `a fresh id is new each time`() {
        let residents = [Resident.ID(), Resident.ID()]
        #expect(residents[0] != residents[1])
        let events = [TownEvent.ID(), TownEvent.ID()]
        #expect(events[0] != events[1])
        let interests = [Interest.ID(), Interest.ID()]
        #expect(interests[0] != interests[1])
        let scenes = [SceneID(), SceneID()]
        #expect(scenes[0] != scenes[1])
    }

    // MARK: - Schedule

    @Test
    func `a schedule keeps its due times and pending responses`() {
        let post = Post.ID()
        let pending = Schedule.PendingResponse(post: post, dueAt: TownFixtures.anHourLater)
        var schedule = Schedule(
            nextOrdinarySceneDue: TownFixtures.anHourLater,
            lastRanAt: TownFixtures.movedIn,
        )
        #expect(schedule.pendingResponses.isEmpty)
        schedule.pendingResponses.append(pending)
        #expect(schedule.nextOrdinarySceneDue == TownFixtures.anHourLater)
        #expect(schedule.lastRanAt == TownFixtures.movedIn)
        #expect(schedule.pendingResponses == [pending])
        #expect(pending.post == post)
        #expect(pending.dueAt == TownFixtures.anHourLater)
    }

    // MARK: - TownValueError

    @Test
    func `an error never repeats the text it rejected`() throws {
        let marker = "SECRET-DIARY-LINE"
        let errors = [
            #expect(throws: TownValueError.self) {
                try YourPostText(marker + TownFixtures.text(140))
            },
            #expect(throws: TownValueError.self) {
                try YourPostText(marker + "\n" + marker)
            },
            #expect(throws: TownValueError.self) {
                try Resident.Relationship(
                    resident: Resident.ID(),
                    description: marker + "\n" + marker,
                )
            },
            #expect(throws: TownValueError.self) {
                try DisplayName(marker + TownFixtures.text(20))
            },
        ]
        for error in errors {
            let rejection = try #require(error)
            #expect(!String(describing: rejection).contains(marker))
            #expect(!String(reflecting: rejection).contains(marker))
        }
    }
}
