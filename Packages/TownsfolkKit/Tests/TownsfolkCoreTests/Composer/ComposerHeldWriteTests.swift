import Foundation
import Testing
import TownsfolkCore

/// A write that waits: it reports each post it is handed, then holds until released, so a
/// test can act while the store call is still open.
private final class HeldWrite: Sendable {
    private let enteredStream: AsyncStream<Post>
    private let enteredContinuation: AsyncStream<Post>.Continuation
    private let releaseStream: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    /// What the composer calls in place of the store.
    var write: ComposerViewModel.Write {
        { [enteredContinuation, releaseStream] post in
            enteredContinuation.yield(post)
            for await _ in releaseStream {
                break
            }
        }
    }

    init() {
        (enteredStream, enteredContinuation) = AsyncStream.makeStream(of: Post.self)
        (releaseStream, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    /// The post the composer handed over, once the write has begun.
    func entered() async -> Post? {
        var iterator = enteredStream.makeAsyncIterator()
        return await iterator.next()
    }

    /// Lets the held write return.
    func release() {
        releaseContinuation.yield()
    }
}

/// Edits made while your post is still being stored survive its success (F1, PR #68).
@MainActor
@Suite("Composer while storing")
struct ComposerHeldWriteTests {
    private static let mikas = ComposerFixtures.mikasOven()
    private static let juns = ReplyTarget(
        postID: Post.ID(),
        author: .resident(name: "Jun"),
        text: "Is that… good?",
    )

    @Test
    func `text and a reply target chosen while storing are kept when the write returns`(
    ) async throws {
        let held = HeldWrite()
        let model = ComposerViewModel(write: held.write) { ComposerFixtures.now }
        model.replyChosen(to: Self.mikas)
        model.textChanged(to: "First.")
        let posting = Task { await model.returnPressed() }
        let posted = try #require(await held.entered())

        model.textChanged(to: "Second, typed meanwhile.")
        model.replyChosen(to: Self.juns)
        held.release()
        await posting.value

        #expect(posted.text == "First.")
        #expect(posted.replyTarget == Self.mikas.postID)
        #expect(model.text == "Second, typed meanwhile.")
        #expect(model.replyTarget == Self.juns)
    }

    @Test
    func `text typed while storing is kept, and the reply it was sent with goes`() async {
        let held = HeldWrite()
        let model = ComposerViewModel(write: held.write) { ComposerFixtures.now }
        model.replyChosen(to: Self.mikas)
        model.textChanged(to: "First.")
        let posting = Task { await model.returnPressed() }
        _ = await held.entered()

        model.textChanged(to: "Second.")
        held.release()
        await posting.value

        #expect(model.text == "Second.")
        #expect(model.replyTarget == nil)
    }

    @Test
    func `with nothing edited while storing, the field clears and reply mode ends`(
    ) async {
        let held = HeldWrite()
        let model = ComposerViewModel(write: held.write) { ComposerFixtures.now }
        model.replyChosen(to: Self.mikas)
        model.textChanged(to: "First.")
        let posting = Task { await model.returnPressed() }
        _ = await held.entered()
        held.release()
        await posting.value

        #expect(model.text.isEmpty)
        #expect(model.replyTarget == nil)
    }
}
