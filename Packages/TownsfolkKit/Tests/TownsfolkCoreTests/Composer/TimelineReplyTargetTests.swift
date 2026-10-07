import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// What the timeline hands the composer to reply to, and when Town › Reply can act
/// (REQ-005, REQ-008).
@MainActor
@Suite("Timeline reply targets")
struct TimelineReplyTargetTests {
    /// Top to bottom: Jun's post, an event row, your post, and Mika's post.
    private struct Board {
        let mikas: Post
        let yours: Post
        let juns: Post
        let model: TimelineViewModel

        @MainActor
        init(displayName: DisplayName?) throws {
            mikas = try Fixtures.post(Fixtures.mika, "11:00:00", "Bread is out.")
            yours = try Fixtures.yours("11:10:00", "Learning Rust today.")
            juns = try Fixtures.post(Fixtures.jun, "12:00:00", "Told you.")
            let snapshot = try TimelineSnapshot(entries: [
                .post(mikas), .post(yours), .post(juns),
                .event(Fixtures.event("11:30:00", "It started raining.")),
            ])
            model = Fixtures.model(
                snapshot,
                clock: ManualClock(start: Fixtures.at("13:00:00")),
                displayName: displayName,
            )
        }
    }

    @Test
    func `a resident's post is replied to under the resident's name`() throws {
        let board = try Board(displayName: DisplayName("Tomo"))
        #expect(board.model.replyTarget(for: board.mikas.id) == ReplyTarget(
            postID: board.mikas.id,
            name: "Mika",
            text: "Bread is out.",
        ))
    }

    @Test
    func `your post is replied to under your name, or You with none stored`() throws {
        let named = try Board(displayName: DisplayName("Tomo"))
        #expect(named.model.replyTarget(for: named.yours.id)?.name == "Tomo")
        #expect(named.model.replyTarget(for: named.yours.id)?.text == "Learning Rust today.")

        let unnamed = try Board(displayName: nil)
        #expect(unnamed.model.replyTarget(for: unnamed.yours.id)?.name == "You")
    }

    @Test
    func `a post the rows do not show cannot be replied to`() throws {
        let board = try Board(displayName: DisplayName("Tomo"))
        #expect(board.model.replyTarget(for: Post.ID()) == nil)
    }

    @Test
    func `with no post selected there is nothing to reply to, and with one it is the target`(
    ) throws {
        let board = try Board(displayName: DisplayName("Tomo"))
        let model = board.model
        #expect(model.selectedReplyTarget == nil)

        model.downArrowPressed()
        #expect(model.selectedReplyTarget?.postID == board.juns.id)

        model.postSelected(board.yours.id)
        #expect(model.selectedReplyTarget?.postID == board.yours.id)

        // Focus leaving the posts — to the composer, or nowhere — clears the selection.
        model.postSelected(nil)
        #expect(model.selectedReplyTarget == nil)
    }

    @Test
    func `leaving the composer selects the topmost post and asks for focus`() throws {
        let board = try Board(displayName: DisplayName("Tomo"))
        let model = board.model
        let request = model.focusRequest

        model.composerDismissed()
        #expect(model.selectedPostID == board.juns.id)
        #expect(model.focusRequest == request + 1)
    }

    @Test
    func `leaving the composer keeps a post already selected`() throws {
        let board = try Board(displayName: DisplayName("Tomo"))
        let model = board.model
        model.postSelected(board.mikas.id)
        model.composerDismissed()
        #expect(model.selectedPostID == board.mikas.id)
    }

    @Test
    func `leaving the composer over an empty timeline selects nothing`() {
        let model = Fixtures.model(
            TimelineSnapshot(entries: []),
            clock: ManualClock(start: Fixtures.at("13:00:00")),
            displayName: nil,
        )
        let request = model.focusRequest
        model.composerDismissed()
        #expect(model.selectedPostID == nil)
        #expect(model.focusRequest == request + 1)
    }
}
