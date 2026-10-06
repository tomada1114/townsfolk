import SwiftUI

/// The design lock's shared values (ADR-0008 › Decision), in the one place every view's
/// private `Layout` enum reads them from.
///
/// Presentation only, so it lives in `TownsfolkUI` and never in `TownsfolkCore`, and it
/// stays internal: `App/` reaches a size through a view's `public static` instead of
/// spelling one. A value changes here only when ADR-0008 changes first.
enum DesignLock {
    /// The spacing scale: 4, 8, 12, 16, 32 pt. Nothing in a layout falls between them.
    enum Spacing {
        /// A post's header to its text.
        static let extraSmall: CGFloat = 4
        /// The posts of a group, a quote line to its first post, the status line to the
        /// composer, and the rows of the profile popover.
        static let small: CGFloat = 8
        /// Each side of the hairline between groups and event rows.
        static let medium: CGFloat = 12
        /// The window edge to the content, and the profile popover's padding.
        static let large: CGFloat = 16
        /// The margin of a full-window state, and the gap between its blocks.
        static let extraLarge: CGFloat = 32
    }

    /// Window and popover sizes (ADR-0008 › Window sizing; ADR-0001).
    enum Window {
        /// The town window's width when it first opens.
        static let defaultWidth: CGFloat = 380
        /// The town window's height when it first opens.
        static let defaultHeight: CGFloat = 680
        /// The narrowest the town window may get.
        static let minimumWidth: CGFloat = 320
        /// The shortest the town window may get.
        static let minimumHeight: CGFloat = 440
        /// The resident profile popover's width.
        static let profilePopoverWidth: CGFloat = 280
        /// The Settings window's one pane.
        static let settingsWidth: CGFloat = 480
    }

    /// The timeline's metrics (ADR-0008 › Timeline metrics, › Type).
    enum Timeline {
        /// The text column's cap, gutter included; a wider window centers it.
        static let textColumnMaxWidth: CGFloat = 560
        /// The gutter left of the shared text edge, where the thread line and the quote
        /// and event symbols hang.
        static let gutter: CGFloat = 16
        /// The thread line's width, drawn with round caps.
        static let threadLineWidth: CGFloat = 2
        /// The side of the square, borderless hover Reply button.
        static let replyButtonSide: CGFloat = 28
        /// Extra line spacing under post text, on top of `.body`'s own.
        static let postLineSpacing: CGFloat = 2
    }

    /// The only custom animations, all opacity (ADR-0008 › Motion), in seconds. Under
    /// Reduce Motion the pill's scroll jumps and the fades stay.
    enum Motion {
        /// A new post fades in, ease-out.
        static let postFadeIn: TimeInterval = 0.2
        /// A new post's Lamplight wash fades out, ease-in.
        static let washFadeOut: TimeInterval = 3
        /// The status line crossfades between two lines.
        static let statusLineCrossfade: TimeInterval = 0.2
        /// The new-posts pill fades in or out.
        static let pillFade: TimeInterval = 0.15
        /// The new-posts pill's scroll to the top.
        static let pillScroll: TimeInterval = 0.3
        /// A founding step's check mark fades in.
        static let foundingCheckFadeIn: TimeInterval = 0.15
    }

    /// The two custom colors, each a Color Set in `TownsfolkUI`'s
    /// `Resources/Colors.xcassets` with Any, Dark, and High Contrast variants (ADR-0008 ›
    /// Custom colors). Everything else is a semantic system color.
    ///
    /// Read from `.module`, never the main bundle: a `#Preview` host has no app asset
    /// catalog, so a main-bundle lookup renders clear there (ADR-0008 › Amended).
    enum Palette {
        /// Metadata text and the symbols beside it. Never post text, never a fill.
        static let secondaryText = Color("SecondaryText", bundle: .module)
        /// The wash behind a newly arrived post. Decoration only: never text, a symbol, a
        /// control, a border, a selection, a lasting surface, or the only sign of anything.
        static let lamplight = Color("Lamplight", bundle: .module)
    }
}
