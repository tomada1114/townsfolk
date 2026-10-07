import SwiftUI
import TownsfolkCore

/// Layout metrics for ``PostGroupView`` and ``QuoteLine``, drawn from the design lock.
private enum Layout {
    /// Between the posts of a group, and from a quote line to its first post.
    static let spacing = DesignLock.Spacing.small
    static let gutter = DesignLock.Timeline.gutter
    static let threadLineWidth = DesignLock.Timeline.threadLineWidth
}

/// The one-line quote of the older post a group replies to, its symbol hanging in the
/// gutter; it truncates before any post text does.
struct QuoteLine: View {
    let quote: TimelineQuote
    let model: TimelineViewModel

    var body: some View {
        Text(model.line(of: quote))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, Layout.gutter)
            .overlay(alignment: .topLeading) {
                Image(systemName: "arrowshape.turn.up.left")
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .foregroundStyle(DesignLock.Palette.secondaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(model.reading(of: quote)))
            .accessibilityIdentifier("quoteLine")
    }
}

/// One group: its quote line, then its posts oldest first, joined by a thread line in
/// the gutter when it is a scene. VoiceOver reads it as one container.
struct PostGroupView: View {
    let group: TimelinePostGroup
    let model: TimelineViewModel
    let focus: FocusState<Post.ID?>.Binding
    /// Replies to a post from the composer.
    let reply: (Post.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            if let quote = group.quote {
                QuoteLine(quote: quote, model: model)
            }
            VStack(alignment: .leading, spacing: Layout.spacing) {
                ForEach(group.posts) { post in
                    PostRow(post: post, model: model, focus: focus) {
                        reply(post.id)
                    }
                    .id(post.id)
                }
            }
            .padding(.leading, Layout.gutter)
            .background(alignment: .leading) {
                if group.isScene {
                    Capsule()
                        .fill(.separator)
                        .frame(width: Layout.threadLineWidth)
                        .frame(width: Layout.gutter)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.reading(of: group)))
        .accessibilityIdentifier("postGroup")
    }
}
