import SwiftUI
import TownsfolkCore

/// The width previews show the composer at, and its narrowest.
private enum PreviewSize {
    static let defaultWidth = DesignLock.Window.defaultWidth
    static let minimumWidth = DesignLock.Window.minimumWidth
    static let margin = DesignLock.Spacing.large
    static let twelveLeft = 128
    static let threeOver = 143
}

/// Composers in each state worth seeing, with no store behind them.
@MainActor
private enum ComposerPreviewData {
    static let words = "Learning Rust today and the borrow checker keeps winning every round "

    static let mikasOven = ReplyTarget(
        postID: Post.ID(),
        author: .resident(name: "Mika"),
        text: "The oven made a goose noise again.",
    )

    /// `count` characters of ``words``, ending on a letter so trimming keeps them all.
    static func text(length count: Int) -> String {
        let repeated = String(repeating: words, count: count / words.count + 1)
        return String(repeated.prefix(count - 1)) + "s"
    }

    static func composer(_ text: String, replyingTo target: ReplyTarget? = nil) -> some View {
        ComposerView(
            model: ComposerViewModel(text: text, replyTarget: target),
            townName: "Maplewood",
            yourName: "Tomo",
        )
        .padding(PreviewSize.margin)
        .background(.background)
    }
}

#Preview("Empty with placeholder") {
    ComposerPreviewData.composer("")
        .frame(width: PreviewSize.defaultWidth)
}

#Preview("Empty with placeholder, dark") {
    ComposerPreviewData.composer("")
        .frame(width: PreviewSize.defaultWidth)
        .preferredColorScheme(.dark)
}

#Preview("Typing") {
    ComposerPreviewData.composer("Learning Rust today. Wish me luck.")
        .frame(width: PreviewSize.defaultWidth)
}

#Preview("12 left") {
    ComposerPreviewData.composer(ComposerPreviewData.text(length: PreviewSize.twelveLeft))
        .frame(width: PreviewSize.defaultWidth)
}

#Preview("3 over") {
    ComposerPreviewData.composer(ComposerPreviewData.text(length: PreviewSize.threeOver))
        .frame(width: PreviewSize.defaultWidth)
}

#Preview("3 over, dark") {
    ComposerPreviewData.composer(ComposerPreviewData.text(length: PreviewSize.threeOver))
        .frame(width: PreviewSize.defaultWidth)
        .preferredColorScheme(.dark)
}

#Preview("Replying") {
    ComposerPreviewData.composer(
        "Poor oven. Maybe it wants a name?",
        replyingTo: ComposerPreviewData.mikasOven,
    )
    .frame(width: PreviewSize.defaultWidth)
}

#Preview("Replying, dark") {
    ComposerPreviewData.composer(
        "Poor oven. Maybe it wants a name?",
        replyingTo: ComposerPreviewData.mikasOven,
    )
    .frame(width: PreviewSize.defaultWidth)
    .preferredColorScheme(.dark)
}

#Preview("Replying, 320 pt wide") {
    ComposerPreviewData.composer("", replyingTo: ComposerPreviewData.mikasOven)
        .frame(width: PreviewSize.minimumWidth)
}
