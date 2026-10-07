import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = ComposerFixtures

/// Replying, focus, and the keys that move between modes (REQ-002, REQ-005 – REQ-007).
@MainActor
@Suite("Composer replying")
struct ComposerReplyTests {
    @Test
    func `choosing Reply enters reply mode, shows the chip, and asks for focus`() {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        let target = Fixtures.mikasOven()
        let focus = model.focusRequest

        model.replyChosen(to: target)
        #expect(model.replyTarget == target)
        #expect(model.focusRequest == focus + 1)
        #expect(model.replyChip?.key == "composer.reply.chip")
        #expect(
            model.replyChip?.resolved(in: .english)
                == "Replying to Mika \"The oven made a goose noise again.\"",
        )
        #expect(model.replyChipReading?.key == "composer.reply.reading")
        #expect(
            model.replyChipReading?.resolved(in: .english)
                == "Replying to Mika: The oven made a goose noise again.",
        )
    }

    @Test
    func `no chip shows while not replying`() {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        #expect(model.replyChip == nil)
        #expect(model.replyChipReading == nil)
    }

    @Test
    func `a reply is stored with its target, and the chip goes`() async throws {
        try await withFoundedStore { store, founding, _ in
            let model = Fixtures.composer(store: store)
            let mikas = founding.firstScene.posts[0]
            model.replyChosen(to: ReplyTarget(postID: mikas.id, name: "Mio", text: mikas.text))
            model.textChanged(to: "Poor oven. Maybe it wants a name?")
            await model.returnPressed()

            let posts = try await Fixtures.yourPosts(in: store)
            try #require(posts.count == 1)
            #expect(posts[0].replyTarget == mikas.id)
            #expect(posts[0].text == "Poor oven. Maybe it wants a name?")
            #expect(model.replyTarget == nil)
            #expect(model.replyChip == nil)
            #expect(model.text.isEmpty)
        }
    }

    @Test
    func `replying to your own post works as for a resident's`() async throws {
        try await withFoundedStore { store, _, _ in
            let mine = try YourPostDraft(time: Fixtures.now, text: "Learning Rust today.").make()
            try await store.storeYourPost(mine)
            let model = Fixtures.composer(store: store)
            model.replyChosen(to: ReplyTarget(postID: mine.id, name: "Tomo", text: mine.text))
            #expect(model.replyChip?.resolved(in: .english)
                == "Replying to Tomo \"Learning Rust today.\"")
            model.textChanged(to: "Day two.")
            await model.returnPressed()

            let posts = try await Fixtures.yourPosts(in: store)
            #expect(posts.compactMap(\.replyTarget) == [mine.id])
        }
    }

    @Test
    func `the cancel button leaves reply mode and keeps the text`() {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        model.replyChosen(to: Fixtures.mikasOven())
        model.textChanged(to: "Poor oven.")
        model.cancelReplyChosen()
        #expect(model.replyTarget == nil)
        #expect(model.text == "Poor oven.")
    }

    @Test
    func `pressing Esc first leaves reply mode, then leaves the composer`() {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        model.replyChosen(to: Fixtures.mikasOven())
        model.textChanged(to: "Poor oven.")
        let leave = model.focusLeaveRequest

        model.escapePressed()
        #expect(model.replyTarget == nil)
        #expect(model.text == "Poor oven.")
        #expect(model.focusLeaveRequest == leave)

        model.escapePressed()
        #expect(model.focusLeaveRequest == leave + 1)
        #expect(model.text == "Poor oven.")
    }

    @Test
    func `choosing New Post leaves reply mode, keeps the text, and asks for focus`() {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        model.replyChosen(to: Fixtures.mikasOven())
        model.textChanged(to: "Hello")
        let focus = model.focusRequest

        model.newPostChosen()
        #expect(model.replyTarget == nil)
        #expect(model.text == "Hello")
        #expect(model.focusRequest == focus + 1)
    }

    @Test
    func `choosing Reply on another post replaces the target`() {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        model.replyChosen(to: Fixtures.mikasOven())
        let juns = ReplyTarget(postID: Post.ID(), name: "Jun", text: "Is that… good?")
        model.replyChosen(to: juns)
        #expect(model.replyTarget == juns)
    }

    @Test
    func `the menu and button titles are catalog resources`() {
        #expect(ComposerViewModel.newPostTitle.key == "town.menu.newPost")
        #expect(ComposerViewModel.newPostTitle.resolved(in: .english) == "New Post")
        #expect(ComposerViewModel.replyTitle.key == "town.menu.reply")
        #expect(ComposerViewModel.replyTitle.resolved(in: .english) == "Reply")
        #expect(ComposerViewModel.replyButtonTitle.key == "timeline.post.replyButton")
        #expect(ComposerViewModel.replyButtonTitle.resolved(in: .english) == "Reply")
        #expect(ComposerViewModel.cancelReplyTitle.key == "composer.reply.cancel")
        #expect(ComposerViewModel.cancelReplyTitle.resolved(in: .english) == "Cancel Reply")
    }
}
