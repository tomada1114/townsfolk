import SwiftUI
import TownsfolkCore

/// The bounds of every post arriving live, gathered so the timeline can draw each one's
/// wash across the window's full width while the post itself sits in the text column.
struct ArrivalWashes: PreferenceKey {
    /// One arriving post and where its row is.
    struct Wash: Identifiable {
        let id: Post.ID
        let bounds: Anchor<CGRect>
    }

    static var defaultValue: [Wash] {
        []
    }

    static func reduce(value: inout [Wash], nextValue: () -> [Wash]) {
        value += nextValue()
    }
}

/// The Lamplight band behind a newly arrived post: square-cornered, as tall as the row,
/// fading out over 3 s (ease-in, so it lingers before it goes). Decoration only — the
/// time text also says the post is new. Once faded it tells the timeline, so the row
/// shows plainly from then on.
struct ArrivalWash: View {
    let id: Post.ID
    let model: TimelineViewModel
    @State private var hasFaded = false

    var body: some View {
        Rectangle()
            .fill(DesignLock.Palette.lamplight)
            .opacity(hasFaded ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: DesignLock.Motion.washFadeOut)) {
                    hasFaded = true
                } completion: {
                    model.arrivalShown(id)
                }
            }
            .accessibilityHidden(true)
    }
}
