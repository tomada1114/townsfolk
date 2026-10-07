import Foundation
import Testing
import TownsfolkCore

/// What the caller hands the writer (REQ-002): 1–3 living speakers from the roster and
/// 1–3 distinct seeds the writer can render. A request that breaks one is refused when it
/// is made, so the writer never meets it.
@Suite("SceneRequest")
struct SceneRequestTests {
    @Test
    func `a request keeps its speakers and seeds in the order given`() throws {
        let cast = try WritingCast()
        let seeds: [SceneSeed] = [.topic("new bread"), .profile(cast.jun.id, .worry)]

        let request = try cast.request(speakers: [cast.jun, cast.mika], seeds: seeds)

        #expect(request.speakers == [cast.jun.id, cast.mika.id])
        #expect(request.seeds == seeds)
        #expect(request.residents == cast.residents)
        #expect(request.you.value == "Tomo")
    }

    @Test
    func `no speaker, or more than three, is refused`() throws {
        let cast = try WritingCast()
        let extra = try ResidentDraft(name: "Ren").make()
        var roster = cast.residents
        roster.append(extra)
        #expect(throws: SceneRequestError.speakerCount(0)) {
            try cast.request(speakers: [], seeds: [.topic("bread")])
        }
        #expect(throws: SceneRequestError.speakerCount(4)) {
            try SceneRequest(
                you: DisplayName("Tomo"),
                town: WritingFixtures.town(),
                residents: roster,
                speakers: [cast.mika.id, cast.jun.id, cast.aki.id, extra.id],
                seeds: [.topic("bread")],
            )
        }
    }

    @Test
    func `the same speaker twice is refused`() throws {
        let cast = try WritingCast()
        #expect(throws: SceneRequestError.duplicateSpeaker) {
            try cast.request(speakers: [cast.mika, cast.mika], seeds: [.topic("bread")])
        }
    }

    @Test
    func `a speaker who moved out, or is not in the roster, is refused`() throws {
        let cast = try WritingCast()
        let stranger = try ResidentDraft(name: "Ren").make()
        #expect(throws: SceneRequestError.speakerNotLiving) {
            try cast.request(speakers: [cast.sora], seeds: [.topic("bread")])
        }
        #expect(throws: SceneRequestError.speakerNotLiving) {
            try cast.request(speakers: [stranger], seeds: [.topic("bread")])
        }
    }

    @Test
    func `no seed, or more than three, is refused`() throws {
        let cast = try WritingCast()
        #expect(throws: SceneRequestError.seedCount(0)) {
            try cast.request(speakers: [cast.mika], seeds: [])
        }
        #expect(throws: SceneRequestError.seedCount(4)) {
            try cast.request(
                speakers: [cast.mika],
                seeds: [.topic("a"), .topic("b"), .topic("c"), .topic("d")],
            )
        }
    }

    @Test
    func `the same seed twice is refused`() throws {
        let cast = try WritingCast()
        #expect(throws: SceneRequestError.duplicateSeed) {
            try cast.request(speakers: [cast.mika], seeds: [.topic("bread"), .topic("bread")])
        }
    }

    @Test
    func `a profile seed of someone not in the roster is refused`() throws {
        let cast = try WritingCast()
        #expect(throws: SceneRequestError.unknownResident) {
            try cast.request(speakers: [cast.mika], seeds: [.profile(Resident.ID(), .hobby)])
        }
    }

    @Test
    func `a post seed that is not yours is refused`() throws {
        let cast = try WritingCast()
        let theirs = try cast.post(by: cast.jun, "Bread is out.", minute: 1)
        #expect(throws: SceneRequestError.seedPostNotYours) {
            try cast.request(
                speakers: [cast.mika],
                seeds: [.yourPost(theirs, quoted: true, leadSpeaker: nil)],
            )
        }
    }

    @Test
    func `a lead speaker who is not one of the speakers is refused`() throws {
        let cast = try WritingCast()
        let yours = try YourPostDraft().make()
        #expect(throws: SceneRequestError.leadNotSpeaker) {
            try cast.request(
                speakers: [cast.mika],
                seeds: [.yourPost(yours, quoted: true, leadSpeaker: cast.jun.id)],
            )
        }
    }

    @Test
    func `a lead speaker among the speakers is taken`() throws {
        let cast = try WritingCast()
        let yours = try YourPostDraft().make()
        let seed = SceneSeed.yourPost(yours, quoted: false, leadSpeaker: cast.jun.id)

        let request = try cast.request(speakers: [cast.mika, cast.jun], seeds: [seed])

        #expect(request.seeds == [seed])
    }
}
