import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// The timeline keeps one open profile, and only the latest ask opens (ux-flows F6).
@MainActor
@Suite("Profile presentation")
struct ProfilePresentationTests {
    private static func profile(_ name: String) throws -> ResidentProfile {
        let resident = try Resident(
            id: Resident.ID(),
            name: name,
            profile: StoreFixtures.profile(),
            movedInAt: StoreFixtures.morning,
        )
        return ResidentProfile(
            resident: resident,
            residents: [],
            interests: [],
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: Calendar(identifier: .gregorian),
        )
    }

    private static func model() throws -> TimelineViewModel {
        try Fixtures.model(
            TimelineSnapshot(entries: []),
            clock: ManualClock(start: Fixtures.at("13:00:00")),
        )
    }

    @Test
    func `of two overlapping reads, only the latest ask opens`() throws {
        let model = try Self.model()
        let (first, second) = (Post.ID(), Post.ID())
        let mika = try Self.profile("Mika")
        let jun = try Self.profile("Jun")
        let older = model.beginProfile()
        let newer = model.beginProfile()
        model.finishProfile(newer, postID: second, profile: jun)
        model.finishProfile(older, postID: first, profile: mika)
        #expect(model.presentedProfile?.postID == second)
        #expect(model.presentedProfile?.profile == jun)
    }

    @Test
    func `an earlier read finishing first is replaced by the newer ask's`() throws {
        let model = try Self.model()
        let (first, second) = (Post.ID(), Post.ID())
        let older = model.beginProfile()
        try model.finishProfile(older, postID: first, profile: Self.profile("Mika"))
        let newer = model.beginProfile()
        let jun = try Self.profile("Jun")
        model.finishProfile(newer, postID: second, profile: jun)
        #expect(model.presentedProfile?.postID == second)
        #expect(model.presentedProfile?.profile == jun)
    }

    @Test
    func `closing drops a read still under way, and a missing resident opens nothing`() throws {
        let model = try Self.model()
        let post = Post.ID()
        let pending = model.beginProfile()
        model.profileDismissed()
        try model.finishProfile(pending, postID: post, profile: Self.profile("Mika"))
        #expect(model.presentedProfile == nil)
        model.finishProfile(model.beginProfile(), postID: post, profile: nil)
        #expect(model.presentedProfile == nil)
    }

    @Test
    func `choosing a post with no profile to read opens nothing`() async throws {
        let model = try Self.model()
        await model.profileChosen(for: Post.ID())
        #expect(model.presentedProfile == nil)
    }
}
