import SwiftUI
import TownsfolkCore

/// Layout metrics for ``PostRow``, drawn from the design lock.
private enum Layout {
    static let headerToText = DesignLock.Spacing.extraSmall
    static let headerGap = DesignLock.Spacing.extraSmall
    static let lineSpacing = DesignLock.Timeline.postLineSpacing
    static let fadeIn = DesignLock.Motion.postFadeIn
}

/// One post (ux-flows S1): the header — the name, then the relative time — and the text,
/// which always wraps and is never cut short. Selectable with the keyboard and shown
/// selected by the system focus ring alone, with no fill.
///
/// A post that arrives live fades in over 200 ms and reports its bounds, so the timeline
/// draws the Lamplight wash behind it across the window's full width.
struct PostRow: View {
    let post: TimelinePost
    let model: TimelineViewModel
    let focus: FocusState<Post.ID?>.Binding
    @State private var hasFadedIn = false

    var body: some View {
        let isArriving = model.isArrivingLive(post.id)
        VStack(alignment: .leading, spacing: Layout.headerToText) {
            header
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
        .focusable()
        .focused(focus, equals: post.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.reading(of: post)))
        .accessibilityIdentifier("postRow")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.headerGap) {
            switch post.author {
            case let .resident(name):
                Text(verbatim: name)
                    .font(.headline)

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
