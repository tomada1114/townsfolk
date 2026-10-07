import Foundation
import Observation

/// The composer (ux-flows S1, F3, F4): the one line you post to the town as yourself,
/// new or in reply to any post (requirements §3.5).
///
/// Line breaks become spaces as you type, and the counter and whether Return posts follow
/// the trimmed length (`docs/design/ux-guidelines.md:73-81`). Return stores your post
/// through ``TownStore/storeYourPost(_:)`` in one transaction and clears the field; there
/// is no pending state, since the timeline shows the post from the store's committed
/// change (ux-guidelines.md:67). A post that cannot be posted, or a write the store
/// refuses, leaves everything as typed and shows nothing.
///
/// It posts whatever the model's availability — nothing here reads it
/// (`docs/product/ux-flows.md:151-152`): the town's responses are the engine's, scheduled
/// from what this stores. Construction reads and writes nothing, and nothing typed is
/// ever logged (`.claude/rules/swift.md` › Logging).
@MainActor
@Observable
public final class ComposerViewModel {
    /// How a post reaches the store: ``TownStore/storeYourPost(_:)`` in the app, and in a
    /// test a write it can hold open.
    package typealias Write = @Sendable (Post) async throws(TownStoreError) -> Void

    /// The Town menu's New Post command (⌘N).
    public static var newPostTitle: LocalizedStringResource {
        ComposerWording.newPost
    }

    /// The Town menu's Reply command (⌘R).
    public static var replyTitle: LocalizedStringResource {
        ComposerWording.reply
    }

    /// The label of the hover ↩ Reply button on a post.
    public static var replyButtonTitle: LocalizedStringResource {
        ComposerWording.replyButton
    }

    /// The label of the chip's ✕ button.
    public static var cancelReplyTitle: LocalizedStringResource {
        ComposerWording.cancelReply
    }

    /// What the field shows: as typed, with each line break turned into a space.
    public private(set) var text: String
    /// The post being replied to, or `nil` for a new post.
    public private(set) var replyTarget: ReplyTarget?
    /// Counts up each time the composer asks the view to give it focus — on ⌘N and on
    /// choosing Reply.
    public private(set) var focusRequest = 0
    /// Counts up each time Esc, outside reply mode, asks the view to hand focus to the
    /// timeline.
    public private(set) var focusLeaveRequest = 0
    /// Whether a post is being stored, so a second Return meanwhile stores nothing.
    private var isPosting = false

    @ObservationIgnored private let write: Write?
    @ObservationIgnored private let tuning: Tuning
    @ObservationIgnored private let now: @Sendable () -> Date

    /// The counter under the field, or `nil` while more than 20 characters remain.
    public var counter: ComposerCounter? {
        ComposerCounter(length: trimmedLength, limit: tuning.yourPost.yourPostLength.upperBound)
    }

    /// Whether Return would post: 1–140 characters after trimming.
    public var canPost: Bool {
        tuning.yourPost.yourPostLength.contains(trimmedLength)
    }

    private var trimmedLength: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    /// Creates the composer over the town's store, with an empty field.
    ///
    /// - Parameters:
    ///   - store: Where your post is stored.
    ///   - tuning: Your post's length (`tuning.yourPost.yourPostLength`).
    ///   - now: The date a post is stored with.
    public convenience init(
        store: TownStore,
        tuning: Tuning = .default,
        now: @escaping @Sendable () -> Date = { Date.now },
    ) {
        self.init(
            write: { post throws(TownStoreError) in try await store.storeYourPost(post) },
            text: "",
            replyTarget: nil,
            tuning: tuning,
            now: now,
        )
    }

    /// Creates a composer with an empty field that stores through `write` — for a test that
    /// holds the store call open.
    package convenience init(write: @escaping Write, now: @escaping @Sendable () -> Date) {
        self.init(write: write, text: "", replyTarget: nil, tuning: .default, now: now)
    }

    /// Creates a composer already showing `text` and replying to `replyTarget`, with no
    /// store behind it, so Return stores nothing — for a preview, and for a test of what
    /// the composer shows.
    package convenience init(text: String, replyTarget: ReplyTarget?) {
        self.init(write: nil, text: text, replyTarget: replyTarget, tuning: .default) { Date.now }
    }

    private init(
        write: Write?,
        text: String,
        replyTarget: ReplyTarget?,
        tuning: Tuning,
        now: @escaping @Sendable () -> Date,
    ) {
        self.write = write
        self.text = text
        self.replyTarget = replyTarget
        self.tuning = tuning
        self.now = now
    }

    /// The field's placeholder, "Say something to {town}…".
    public static func placeholder(townName: String) -> LocalizedStringResource {
        ComposerWording.placeholder(townName: townName)
    }

    /// The chip's text while replying, "Replying to {name} "{text}"", or `nil`.
    /// `yourName` is your current name, shown when the post replied to is yours.
    public func replyChip(yourName: String) -> LocalizedStringResource? {
        replyTarget.map { target in
            ComposerWording.replyChip(name: name(of: target, yourName: yourName), text: target.text)
        }
    }

    /// What VoiceOver reads for the chip, "Replying to {name}: {text}", or `nil`.
    public func replyChipReading(yourName: String) -> LocalizedStringResource? {
        replyTarget.map { target in
            ComposerWording.replyReading(
                name: name(of: target, yourName: yourName),
                text: target.text,
            )
        }
    }

    // MARK: Actions

    /// The field's text changed — typed or pasted. Each line break becomes a space; the
    /// input is otherwise kept exactly, never cut.
    public func textChanged(to newText: String) {
        text = String(newText.map { $0.isNewline ? " " : $0 })
    }

    /// Return in the field. With 1–140 characters after trimming, stores your post — you
    /// as author, the trimmed text, the reply target if replying, now — then clears the
    /// field and leaves reply mode. Otherwise, or when the store refuses the write, does
    /// nothing and keeps the input as typed. The field stays editable while the store
    /// works: text typed, or a reply chosen, meanwhile is kept, and only what still
    /// matches the post just stored is cleared.
    public func returnPressed() async {
        guard !isPosting,
              let write,
              let post = try? Post(
                  id: Post.ID(),
                  author: .you,
                  text: text,
                  happenedAt: now(),
                  replyTarget: replyTarget?.postID,
                  tuning: tuning,
              )
        else {
            return
        }
        let submitted = (text: text, replyTarget: replyTarget)
        isPosting = true
        defer { isPosting = false }
        do {
            try await write(post)
        } catch {
            AppLog.composer.error("post not stored: \(String(describing: error), privacy: .public)")
            return
        }
        if text == submitted.text {
            text = ""
        }
        if replyTarget == submitted.replyTarget {
            replyTarget = nil
        }
        AppLog.composer.debug("post stored, reply: \(post.replyTarget != nil, privacy: .public)")
    }

    /// ↩ Reply on a post, or ⌘R with one selected: replies to `target`, keeping what is
    /// typed, and asks for focus.
    public func replyChosen(to target: ReplyTarget) {
        replyTarget = target
        focusRequest += 1
    }

    /// New Post (⌘N): leaves reply mode, keeping what is typed, and asks for focus.
    public func newPostChosen() {
        replyTarget = nil
        focusRequest += 1
    }

    /// The chip's ✕: leaves reply mode, keeping what is typed.
    public func cancelReplyChosen() {
        replyTarget = nil
    }

    /// Esc in the field: leaves reply mode first; outside it, asks the view to hand focus
    /// to the timeline. What is typed stays either way.
    public func escapePressed() {
        if replyTarget != nil {
            replyTarget = nil
        } else {
            focusLeaveRequest += 1
        }
    }

    /// The name the chip shows for `target`'s author.
    private func name(of target: ReplyTarget, yourName: String) -> String {
        switch target.author {
        case let .resident(name):
            name

        case .you:
            yourName
        }
    }
}
