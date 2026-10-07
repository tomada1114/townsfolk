import Foundation
import Testing
import TownsfolkCore

private typealias Fixtures = ComposerFixtures

/// The composer's text, counter, and posting rules (REQ-001 – REQ-004, REQ-009, REQ-010).
@MainActor
@Suite("Composer")
struct ComposerViewModelTests {
    @Test(arguments: [
        ("Hello\nthere", "Hello there"),
        ("Hello\r\nthere", "Hello there"),
        ("Hello\rthere", "Hello there"),
        ("one\ntwo\nthree", "one two three"),
        ("  as typed  ", "  as typed  "),
    ])
    func `line breaks become spaces and nothing else changes`(typed: String, shown: String) {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        model.textChanged(to: typed)
        #expect(model.text == shown)
    }

    /// A trimmed length and the counter it shows: none until 20 remain, then "{n} left",
    /// and "{n} over" past 140.
    @Test(arguments: [
        (0, ComposerCounter?.none),
        (1, nil),
        (119, nil),
        (120, .left(20)),
        (128, .left(12)),
        (140, .left(0)),
        (141, .over(1)),
        (143, .over(3)),
    ])
    func `the counter follows the trimmed length`(length: Int, counter: ComposerCounter?) {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        model.textChanged(to: "  \(Fixtures.text(length: length))  ")
        #expect(model.counter == counter)
    }

    @Test
    func `the counter reads n left, or n over with the warning`() {
        let left = ComposerCounter.left(12)
        #expect(left.title.key == "composer.counter.left")
        #expect(left.title.resolved(in: .english) == "12 left")
        #expect(!left.isOver)

        let over = ComposerCounter.over(3)
        #expect(over.title.key == "composer.counter.over")
        #expect(over.title.resolved(in: .english) == "3 over")
        #expect(over.isOver)
    }

    @Test(arguments: [
        ("", false),
        ("   ", false),
        ("a", true),
        (Fixtures.text(length: 140), true),
        (Fixtures.text(length: 141), false),
    ])
    func `only 1 to 140 trimmed characters can be posted`(text: String, canPost: Bool) {
        let model = ComposerViewModel(text: "", replyTarget: nil)
        model.textChanged(to: text)
        #expect(model.canPost == canPost)
    }

    @Test(arguments: ["a", "Learning Rust today. Wish me luck.", Fixtures.text(length: 140)])
    func `pressing Return stores your post, then clears the field`(text: String) async throws {
        try await withFoundedStore { store, _, _ in
            let model = Fixtures.composer(store: store)
            model.textChanged(to: text)
            await model.returnPressed()

            let posts = try await Fixtures.yourPosts(in: store)
            try #require(posts.count == 1)
            #expect(posts[0].text == text)
            #expect(posts[0].happenedAt == Fixtures.now)
            #expect(posts[0].replyTarget == nil)
            #expect(posts[0].sceneID == nil)
            #expect(model.text.isEmpty)
            #expect(model.counter == nil)
            #expect(model.replyTarget == nil)
        }
    }

    @Test
    func `the post is stored trimmed`() async throws {
        try await withFoundedStore { store, _, _ in
            let model = Fixtures.composer(store: store)
            model.textChanged(to: "   Learning Rust today.\n")
            await model.returnPressed()
            let posts = try await Fixtures.yourPosts(in: store)
            #expect(posts.map(\.text) == ["Learning Rust today."])
        }
    }

    @Test(arguments: ["", "   ", Fixtures.text(length: 141), Fixtures.text(length: 143)])
    func `pressing Return with a blank or too long post does nothing and keeps the input`(
        text: String,
    ) async throws {
        try await withFoundedStore { store, _, _ in
            let model = Fixtures.composer(store: store)
            model.textChanged(to: text)
            await model.returnPressed()
            let stored = try await Fixtures.yourPosts(in: store)
            #expect(stored.isEmpty)
            #expect(model.text == text)
        }
    }

    @Test
    func `with 143 characters the counter reads 3 over, and Return keeps them all`() async throws {
        try await withFoundedStore { store, _, _ in
            let model = Fixtures.composer(store: store)
            let typed = Fixtures.text(length: 143)
            model.textChanged(to: typed)
            #expect(model.counter == .over(3))
            await model.returnPressed()
            let stored = try await Fixtures.yourPosts(in: store)
            #expect(stored.isEmpty)
            #expect(model.text.count == 143)
            #expect(model.counter == .over(3))
        }
    }

    @Test
    func `pressing Return twice at once stores the post once`() async throws {
        try await withFoundedStore { store, _, _ in
            let model = Fixtures.composer(store: store)
            model.textChanged(to: "Once.")
            async let first: Void = model.returnPressed()
            async let second: Void = model.returnPressed()
            _ = await (first, second)
            let stored = try await Fixtures.yourPosts(in: store)
            #expect(stored.map(\.text) == ["Once."])
        }
    }

    @Test
    func `a composer with no store keeps what was typed`() async {
        let model = ComposerViewModel(text: "Hello", replyTarget: nil)
        await model.returnPressed()
        #expect(model.text == "Hello")
    }

    @Test
    func `the composer posts with nothing but the store, whatever the model's state`(
    ) async throws {
        // REQ-010: the composer is built from the store alone, so no availability can stop it.
        try await withFoundedStore { store, _, _ in
            let model = ComposerViewModel(store: store) { Fixtures.now }
            model.textChanged(to: "Still here.")
            await model.returnPressed()
            let stored = try await Fixtures.yourPosts(in: store)
            #expect(stored.map(\.text) == ["Still here."])
        }
    }

    @Test
    func `a write the store refuses keeps the text and the reply target`() async throws {
        try await withFoundedStore { store, _, _ in
            let model = Fixtures.composer(store: store)
            // A reply to a post the store does not hold fails its foreign key.
            let missing = Fixtures.mikasOven()
            model.replyChosen(to: missing)
            model.textChanged(to: "Poor oven.")
            await model.returnPressed()

            let stored = try await Fixtures.yourPosts(in: store)
            #expect(stored.isEmpty)
            #expect(model.text == "Poor oven.")
            #expect(model.replyTarget == missing)
        }
    }

    @Test
    func `a closed store keeps the text`() async throws {
        try await withFoundedStore { store, _, _ in
            let model = Fixtures.composer(store: store)
            try await store.deleteEverything()
            model.textChanged(to: "Anyone?")
            await model.returnPressed()
            #expect(model.text == "Anyone?")
        }
    }

    @Test
    func `the placeholder names the town`() {
        let placeholder = ComposerViewModel.placeholder(townName: "Maplewood")
        #expect(placeholder.key == "composer.placeholder")
        #expect(placeholder.resolved(in: .english) == "Say something to Maplewood…")
    }
}
