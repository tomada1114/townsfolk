import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// Town › Show Profile (⌘I) acts on the selected post's author, and only on a resident
/// (REQ-004, REQ-005).
@MainActor
@Suite("Profile availability")
struct ProfileAvailabilityTests {
    private struct Board {
        let mikas: Post
        let yours: Post
        let model: TimelineViewModel

        @MainActor
        init(selecting selection: (Post, Post) -> Post.ID?) throws {
            let mikasPost = try Fixtures.post(Fixtures.mika, "11:00:00", "Bread is out.")
            let yourPost = try Fixtures.yours("11:10:00", "Learning Rust today.")
            var snapshot = try TimelineSnapshot(entries: [
                .post(mikasPost), .post(yourPost),
                .event(Fixtures.event("11:30:00", "It started raining.")),
            ])
            snapshot.selectedPost = selection(mikasPost, yourPost)
            mikas = mikasPost
            yours = yourPost
            model = try Fixtures.model(snapshot, clock: ManualClock(start: Fixtures.at("13:00:00")))
        }
    }

    @Test
    func `a resident's selected post offers that resident's profile`() throws {
        let board = try Board { mikas, _ in mikas.id }
        #expect(board.model.selectedProfileResident == Fixtures.mika)
    }

    @Test
    func `nothing is offered while no post is selected`() throws {
        let board = try Board { _, _ in nil }
        #expect(board.model.selectedProfileResident == nil)
    }

    @Test
    func `your own selected post offers no profile`() throws {
        let board = try Board { _, yours in yours.id }
        #expect(board.model.selectedProfileResident == nil)
    }

    @Test
    func `the rule reads the post's author`() throws {
        let board = try Board { _, _ in nil }
        let posts = board.model.items.flatMap { item -> [TimelinePost] in
            if case let .group(group) = item {
                return group.posts
            }
            return []
        }
        let resident = try #require(posts.first { $0.id == board.mikas.id })
        let yours = try #require(posts.first { $0.id == board.yours.id })
        #expect(ProfileAvailability.resident(of: resident) == Fixtures.mika)
        #expect(ProfileAvailability.resident(of: yours) == nil)
        #expect(ProfileAvailability.resident(of: nil) == nil)
    }

    @Test
    func `choosing Show Profile asks the selected post's row to open its profile`() throws {
        let board = try Board { mikas, _ in mikas.id }
        #expect(board.model.profileRequest == nil)
        board.model.showProfileChosen()
        let first = try #require(board.model.profileRequest)
        #expect(first.postID == board.mikas.id)
        board.model.showProfileChosen()
        let second = try #require(board.model.profileRequest)
        #expect(second.postID == board.mikas.id)
        #expect(second.serial == first.serial + 1)
    }

    @Test
    func `choosing Show Profile does nothing on your own post`() throws {
        let board = try Board { _, yours in yours.id }
        board.model.showProfileChosen()
        #expect(board.model.profileRequest == nil)
    }

    @Test
    func `no profile model is made for your post, or without a store`() throws {
        let board = try Board { _, _ in nil }
        #expect(board.model.profileModel(for: board.yours.id) == nil)
        #expect(board.model.profileModel(for: board.mikas.id) == nil)
    }
}
