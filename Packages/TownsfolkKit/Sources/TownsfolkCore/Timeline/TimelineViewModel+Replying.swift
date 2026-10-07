import Foundation

/// What the timeline hands the composer to reply to (ux-flows F4): any post it shows, a
/// resident's or yours, and never an event row, which cannot be selected.
extension TimelineViewModel {
    /// The selected post as a reply target — what Town › Reply (⌘R) acts on — or `nil`,
    /// which disables it, while no post is selected.
    public var selectedReplyTarget: ReplyTarget? {
        selectedPostID.flatMap(replyTarget(for:))
    }

    /// Your name as a quote or the composer's chip shows it: your current name, or "You"
    /// with none stored. Read when drawn, so a change in Settings shows at once.
    public var yourName: String {
        if let displayName {
            return displayName.value
        }
        var resource = TimelineWording.you
        resource.locale = environment.locale
        return String(localized: resource)
    }

    /// The posts top to bottom, skipping event rows — the order ↑, ↓, and leaving the
    /// composer select in.
    var postOrder: [Post.ID] {
        items.flatMap { item -> [Post.ID] in
            if case let .group(group) = item {
                return group.posts.map(\.id)
            }
            return []
        }
    }

    /// The post `id` as a reply target, or `nil` when the rows do not show it.
    public func replyTarget(for id: Post.ID) -> ReplyTarget? {
        for case let .group(group) in items {
            if let post = group.posts.first(where: { $0.id == id }) {
                return ReplyTarget(postID: post.id, author: author(of: post), text: post.text)
            }
        }
        return nil
    }

    /// The post's author for the chip: a resident by name, or you, whose name is read
    /// when the chip is drawn.
    private func author(of post: TimelinePost) -> ReplyTarget.Author {
        switch post.author {
        case let .resident(name):
            .resident(name: name)

        case .you:
            .you
        }
    }
}
