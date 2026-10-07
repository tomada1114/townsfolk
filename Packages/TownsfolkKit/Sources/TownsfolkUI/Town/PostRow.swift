import SwiftUI
import TownsfolkCore

/// Layout metrics for ``PostRow``, drawn from the design lock.
private enum Layout {
    static let headerToText = DesignLock.Spacing.extraSmall
    static let headerGap = DesignLock.Spacing.extraSmall
    static let lineSpacing = DesignLock.Timeline.postLineSpacing
    static let fadeIn = DesignLock.Motion.postFadeIn
    static let replyButtonSide = DesignLock.Timeline.replyButtonSide
}

/// The hover ↩ Reply: a 28 × 28 pt borderless button at the trailing end of the header
/// line, labeled "Reply" for VoiceOver and as its tooltip.
private struct PostReplyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(ComposerViewModel.replyButtonTitle, systemImage: "arrowshape.turn.up.left")
                .labelStyle(.iconOnly)
                .frame(width: Layout.replyButtonSide, height: Layout.replyButtonSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(DesignLock.Palette.secondaryText)
        .help(Text(ComposerViewModel.replyButtonTitle))
        .accessibilityIdentifier("postReplyButton")
    }
}

/// One post (ux-flows S1): the header — the name, then the relative time — and the text,
/// which always wraps and is never cut short. Selectable with the keyboard and shown
/// selected by the system focus ring alone, with no fill. Hovering it shows ↩ Reply at
/// the header's trailing end; VoiceOver offers the same as the row's Reply action, and
/// the keyboard as Town › Reply (⌘R). A resident's name is a button opening their
/// profile, as VoiceOver's Show Profile action and Town › Show Profile (⌘I) do; your name
/// is plain text.
///
/// A post that arrives live fades in over 200 ms and reports its bounds, so the timeline
/// draws the Lamplight wash behind it across the window's full width.
struct PostRow: View {
    let post: TimelinePost
    let model: TimelineViewModel
    let focus: FocusState<Post.ID?>.Binding
    /// Replies to this post from the composer.
    let reply: () -> Void
    @State private var hasFadedIn = false
    @State private var isHovering = false

    var body: some View {
        let isArriving = model.isArrivingLive(post.id)
        VStack(alignment: .leading, spacing: Layout.headerToText) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if isHovering {
                        PostReplyButton(action: reply)
                    }
                }
            Text(verbatim: post.text)
                .font(.body)
                .lineSpacing(Layout.lineSpacing)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isArriving && !hasFadedIn ? 0 : 1)
        .onAppear {
            if isArriving {
                withAnimation(.easeOut(duration: Layout.fadeIn)) {
                    hasFadedIn = true
                }
            }
        }
        .anchorPreference(key: ArrivalWashes.self, value: .bounds) { bounds in
            isArriving ? [ArrivalWashes.Wash(id: post.id, bounds: bounds)] : []
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .focusable()
        .focused(focus, equals: post.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.reading(of: post)))
        .accessibilityAction(named: Text(ComposerViewModel.replyButtonTitle), reply)
        .accessibilityActions {
            if !post.isYours {
                Button(ProfileViewModel.showProfileTitle) {
                    model.postSelected(post.id)
                    model.showProfileChosen()
                }
            }
        }
        .accessibilityIdentifier("postRow")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.headerGap) {
            switch post.author {
            case let .resident(name):
                ResidentNameButton(name: name, postID: post.id, model: model) {
                    focus.wrappedValue = post.id
                }

            case let .you(name, marker):
                if let name {
                    Text(verbatim: name)
                        .font(.headline)
                }
                Text(marker)
                    .foregroundStyle(DesignLock.Palette.secondaryText)
            }
            Text(verbatim: "·")
                .foregroundStyle(DesignLock.Palette.secondaryText)
            Text(verbatim: model.time(of: post.happenedAt))
                .foregroundStyle(DesignLock.Palette.secondaryText)
                .help(model.fullTime(of: post.happenedAt))
        }
        .font(.body)
        .lineLimit(1)
    }
}
