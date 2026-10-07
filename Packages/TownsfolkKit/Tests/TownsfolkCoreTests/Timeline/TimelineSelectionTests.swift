import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = TimelineFixtures

/// ↑ and ↓ move the selection between posts, skipping event rows and quote lines
/// (REQ-009).
@MainActor
@Suite("Timeline selection")
struct TimelineSelectionTests {
    /// Top to bottom: a scene of Jun then Sora quoting Mika's post, an event row, your
    /// post, and Mika's post.
    private struct Board {
        let mikas: Post
        let yours: Post
        let juns: Post
        let soras: Post
        let model: TimelineViewModel

        @MainActor
        init() throws {
            let scene = SceneID()
            mikas = try Fixtures.post(Fixtures.mika, "11:00:00", "Bread is out.")
            yours = try Fixtures.yours("11:10:00", "Learning Rust today.")
            juns = try Fixtures.post(
                Fixtures.jun,
                "12:00:00",
                "Told you.",
                scene: scene,
                replyTo: mikas.id,
            )
            soras = try Fixtures.post(Fixtures.sora, "12:00:40", "Or ask?", scene: scene)
            let snapshot = try TimelineSnapshot(entries: [
                .post(mikas), .post(yours), .post(juns), .post(soras),
                .event(Fixtures.event("11:30:00", "It started raining.")),
            ])
            model = try Fixtures.model(snapshot, clock: ManualClock(start: Fixtures.at("13:00:00")))
        }
    }

    @Test
    func `down moves through the posts top to bottom, skipping the event row`() throws {
        let board = try Board()
        var visited: [Post.ID?] = []
        for _ in 0 ..< 5 {
            board.model.downArrowPressed()
            visited.append(board.model.selectedPostID)
        }
        #expect(visited == [
            board.juns.id, board.soras.id, board.yours.id, board.mikas.id, board.mikas.id,
        ])
    }

    @Test
    func `up moves back toward the top and stays on the topmost post`() throws {
        let board = try Board()
        let model = board.model
        model.postSelected(board.mikas.id)
        var visited: [Post.ID?] = []
        for _ in 0 ..< 5 {
            model.upArrowPressed()
            visited.append(model.selectedPostID)
        }
        #expect(visited == [
            board.yours.id, board.soras.id, board.juns.id, board.juns.id, board.juns.id,
        ])
    }

    @Test
    func `with nothing selected, either arrow selects the topmost post`() throws {
        let board = try Board()
        board.model.upArrowPressed()
        #expect(board.model.selectedPostID == board.juns.id)
    }

    @Test
    func `selecting a post by pointer or focus, and clearing it`() throws {
        let board = try Board()
        board.model.postSelected(board.yours.id)
        #expect(board.model.selectedPostID == board.yours.id)
        board.model.downArrowPressed()
        #expect(board.model.selectedPostID == board.mikas.id)
        board.model.postSelected(nil)
        #expect(board.model.selectedPostID == nil)
    }

    @Test
    func `a snapshot may start with a post selected`() throws {
        let probe = try Board()
        var snapshot = TimelineSnapshot(entries: [.post(probe.yours)])
        snapshot.selectedPost = probe.yours.id
        let model = try Fixtures.model(snapshot, clock: ManualClock(start: Fixtures.at("13:00:00")))
        #expect(model.selectedPostID == probe.yours.id)
    }
}
