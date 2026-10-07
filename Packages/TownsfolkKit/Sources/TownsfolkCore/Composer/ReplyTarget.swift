/// The post you are replying to, as the composer's chip shows it: its id, which your
/// post stores as its reply target, and its author and text for the one-line quote. Any
/// post can be a target — a resident's or yours — never an event row
/// (`docs/product/ux-flows.md:78`).
public struct ReplyTarget: Sendable, Equatable {
    /// Who wrote the post replied to.
    public enum Author: Sendable, Equatable {
        /// A resident, by the name the town gave them.
        case resident(name: String)
        /// You. No name is kept: the chip shows your current name when it is drawn, so a
        /// change in Settings shows at once (requirements §3.10).
        case you
    }

    /// The post replied to.
    public let postID: Post.ID
    /// Its author.
    public let author: Author
    /// Its whole text; the chip cuts it to one line.
    public let text: String

    /// Creates a target; ``TimelineViewModel/replyTarget(for:)`` builds one from a post
    /// the timeline shows.
    public init(postID: Post.ID, author: Author, text: String) {
        self.postID = postID
        self.author = author
        self.text = text
    }
}
