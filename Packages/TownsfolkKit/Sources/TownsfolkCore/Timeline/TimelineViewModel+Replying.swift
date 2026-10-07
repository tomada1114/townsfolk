import Foundation

/// What the timeline hands the composer to reply to (ux-flows F4): any post it shows, a
/// resident's or yours, and never an event row, which cannot be selected.
extension TimelineViewModel {
    /// The selected post as a reply target — what Town › Reply (⌘R) acts on — or `nil`,
    /// which disables it, while no post is selected.
    public var selectedReplyTarget: ReplyTarget? {
        selectedPostID.flatMap(replyTarget(for:))
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
                return ReplyTarget(postID: post.id, name: name(of: post.author), text: post.text)
            }
        }
        return nil
    }

    /// The author's name as the chip shows it: a resident's name, or your current name
    /// without "(you)" — "You" with none stored, as a quote line shows it.
    private func name(of author: TimelinePost.Author) -> String {
        switch author {
        case let .resident(name):
            return name

        case let .you(name, _):
            if let name {
                return name
            }
            var resource = TimelineWording.you
            resource.locale = environment.locale
            return String(localized: resource)
        }
    }
}
