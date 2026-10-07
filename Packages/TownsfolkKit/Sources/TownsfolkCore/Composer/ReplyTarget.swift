/// The post you are replying to, as the composer's chip shows it: its id, which your
/// post stores as its reply target, and its author's name and text for the one-line
/// quote. Any post can be a target — a resident's or yours — never an event row
/// (`docs/product/ux-flows.md:78`).
public struct ReplyTarget: Sendable, Equatable {
    /// The post replied to.
    public let postID: Post.ID
    /// Its author's name — your current name, without "(you)", for a post of yours.
    public let name: String
    /// Its whole text; the chip cuts it to one line.
    public let text: String

    /// Creates a target; ``TimelineViewModel/replyTarget(for:)`` builds one from a post
    /// the timeline shows.
    public init(postID: Post.ID, name: String, text: String) {
        self.postID = postID
        self.name = name
        self.text = text
    }
}
