import SwiftUI
import TownsfolkCore

/// Layout metrics for ``TownView``, drawn from the design lock.
private enum Layout {
    static let minimumWidth = DesignLock.Window.minimumWidth
    static let minimumHeight = DesignLock.Window.minimumHeight
    static let columnWidth = DesignLock.Timeline.textColumnMaxWidth
    static let edge = DesignLock.Spacing.large
    static let hairlineGap = DesignLock.Spacing.medium
    static let pillGap = DesignLock.Spacing.small
    static let pillFade = DesignLock.Motion.pillFade
    static let pillScroll = DesignLock.Motion.pillScroll
    /// Below the composer, down to the hairline over the timeline.
    static let composerToHairline = DesignLock.Spacing.medium
    /// How close to the top, in points, still counts as being at the top.
    static let topTolerance: CGFloat = 1
    /// The scroll target before the first row, so a scroll to the top shows the edge too.
    static let topID = "timelineTop"
}

/// The rows inside the scroll view: an edge's worth of space at the top that a scroll
/// to the top lands on, then each row, with every arrival's wash drawn across the full
/// width behind them. A row coming into view may load the next older page.
private struct TimelineRows: View {
    let model: TimelineViewModel
    let focus: FocusState<Post.ID?>.Binding
    let reply: (Post.ID) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Layout.edge)
                .id(Layout.topID)
            ForEach(model.items) { item in
                TimelineRow(
                    item: item,
                    isFirst: item.id == model.items.first?.id,
                    model: model,
                    focus: focus,
                    reply: reply,
                )
                .id(item.id)
                .task { await model.rowAppeared(item.id) }
            }
        }
        .padding(.bottom, Layout.edge)
        .backgroundPreferenceValue(ArrivalWashes.self) { washes in
            GeometryReader { geometry in
                ForEach(washes) { wash in
                    let bounds = geometry[wash.bounds]
                    ArrivalWash(id: wash.id, model: model)
                        .frame(width: geometry.size.width, height: bounds.height)
                        .offset(y: bounds.minY)
                }
            }
        }
    }
}

/// The scrolling timeline: its rows, the new-posts pill over them, the scroll position
/// reported to the model, ↑ and ↓ moving the selection, and focus coming back from the
/// composer.
private struct TimelineList: View {
    let model: TimelineViewModel
    let reply: (Post.ID) -> Void
    @FocusState private var focusedPost: Post.ID?
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                TimelineRows(model: model, focus: $focusedPost, reply: reply)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= Layout.topTolerance
            } action: { _, isAtTop in
                model.scrollPositionChanged(isAtTop: isAtTop)
            }
            .overlay(alignment: .top) { PillSlot(model: model) }
            .onAppear {
                // A selection made before the rows appeared (a preview's) takes focus.
                focusedPost = model.selectedPostID
            }
            .onChange(of: model.scrollToTopRequest) {
                scrollToTop(proxy)
            }
            .onChange(of: model.focusRequest) { _ = followSelection(proxy) }
            .onChange(of: focusedPost) { _, post in
                model.postSelected(post)
            }
            .onKeyPress(.upArrow) {
                model.upArrowPressed()
                return followSelection(proxy)
            }
            .onKeyPress(.downArrow) {
                model.downArrowPressed()
                return followSelection(proxy)
            }
            .accessibilityIdentifier("timeline")
        }
    }

    /// Scrolls to the top over 300 ms, or jumps there under Reduce Motion.
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(Layout.topID, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: Layout.pillScroll)) {
                proxy.scrollTo(Layout.topID, anchor: .top)
            }
        }
    }

    /// Moves focus to the selected post and brings it into view. While the pill shows,
    /// the post is centered, which keeps it clear of the pill's height and 8 pt more in
    /// any window at least 440 pt tall.
    private func followSelection(_ proxy: ScrollViewProxy) -> KeyPress.Result {
        focusedPost = model.selectedPostID
        if let selected = model.selectedPostID {
            proxy.scrollTo(selected, anchor: model.pillTitle == nil ? nil : .center)
        }
        return .handled
    }
}

/// One row in the text column: a hairline above every row but the first, then the group
/// or event row.
private struct TimelineRow: View {
    let item: TimelineItem
    let isFirst: Bool
    let model: TimelineViewModel
    let focus: FocusState<Post.ID?>.Binding
    let reply: (Post.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                Divider()
                    .padding(.vertical, Layout.hairlineGap)
            }
            switch item {
            case let .event(row):
                EventRow(row: row, model: model)

            case let .group(group):
                PostGroupView(group: group, model: model, focus: focus, reply: reply)
            }
        }
        .frame(maxWidth: Layout.columnWidth, alignment: .leading)
        .padding(.horizontal, Layout.edge)
        .frame(maxWidth: .infinity)
    }
}

/// Where the new-posts pill appears, fading in and out over 150 ms on its own, so no
/// other change in the timeline is animated with it.
private struct PillSlot: View {
    let model: TimelineViewModel

    var body: some View {
        ZStack {
            if let title = model.pillTitle {
                NewPostsPill(title: title) {
                    model.scrollToLatestChosen()
                }
                .padding(.top, Layout.pillGap)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Layout.pillFade), value: model.pillTitle == nil)
    }
}

/// The town window's main content (ux-flows S1): the composer at the top, then the
/// timeline, newest first, with the new-posts pill above it, titled with the town's name.
/// The status line joins it later, 8 pt above the composer.
///
/// It renders ``TimelineViewModel`` and ``ComposerViewModel`` and decides nothing; `.task`
/// runs the timeline for as long as the view is on screen, each live arrival's polite
/// announcement is posted as it comes, ↩ Reply on a post hands the composer that post,
/// and Esc leaving the composer hands focus to the timeline.
public struct TownView: View {
    @State private var model: TimelineViewModel
    @State private var composer: ComposerViewModel

    public var body: some View {
        VStack(spacing: 0) {
            ComposerView(model: composer, townName: model.title)
                .frame(maxWidth: Layout.columnWidth)
                .padding(.horizontal, Layout.edge)
                .frame(maxWidth: .infinity)
                .padding(.top, Layout.edge)
                .padding(.bottom, Layout.composerToHairline)
            Divider()
            TimelineList(model: model) { id in
                if let target = model.replyTarget(for: id) {
                    composer.replyChosen(to: target)
                }
            }
        }
        .frame(minWidth: Layout.minimumWidth, minHeight: Layout.minimumHeight)
        .background(.background)
        .navigationTitle(model.title)
        .task { await model.run() }
        .onChange(of: model.announcement) { _, announcement in
            if let announcement {
                AccessibilityNotification
                    .Announcement(AttributedString(localized: announcement.text))
                    .post()
            }
        }
        .onChange(of: composer.focusLeaveRequest) {
            model.composerDismissed()
        }
        .accessibilityIdentifier("townView")
    }

    /// Creates the town window's content over `model` and `composer`, which `App/` builds
    /// over the town's store and a preview builds in a state.
    public init(model: TimelineViewModel, composer: ComposerViewModel) {
        _model = State(initialValue: model)
        _composer = State(initialValue: composer)
    }
}
