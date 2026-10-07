import Foundation

/// Every word the composer (ux-flows S1 and its Replying variant), the hover Reply
/// button, and the Town menu's New Post and Reply (S8) show or read aloud, as String
/// Catalog resources. ``ComposerViewModel`` hands each to the view, which renders it as
/// it is.
///
/// Computed, so each read builds a fresh resource; `package`, so `LocalizationTests` can
/// list every key without the app seeing them.
package enum ComposerWording {
    /// The chip's cancel button, an `xmark` with no visible title.
    package static var cancelReply: LocalizedStringResource {
        LocalizedStringResource(
            "composer.reply.cancel",
            defaultValue: "Cancel Reply",
            bundle: .module,
            comment: """
            Composer: the label of the ✕ button on the replying chip, read by VoiceOver \
            and shown as a tooltip. It leaves reply mode and keeps what you typed.
            """,
        )
    }

    /// The hover button on a post, a reply symbol with no visible title.
    package static var replyButton: LocalizedStringResource {
        LocalizedStringResource(
            "timeline.post.replyButton",
            defaultValue: "Reply",
            bundle: .module,
            comment: """
            Timeline: the label of the reply-symbol button that appears at the end of a \
            post's header on hover, read by VoiceOver and shown as a tooltip.
            """,
        )
    }

    /// The Town menu's command focusing the composer.
    package static var newPost: LocalizedStringResource {
        LocalizedStringResource(
            "town.menu.newPost",
            defaultValue: "New Post",
            bundle: .module,
            comment: """
            Menu bar: the Town menu command (⌘N) that puts the cursor in the composer to \
            write a new post, leaving any reply.
            """,
        )
    }

    /// The Town menu's command replying to the selected post.
    package static var reply: LocalizedStringResource {
        LocalizedStringResource(
            "town.menu.reply",
            defaultValue: "Reply",
            bundle: .module,
            comment: "Menu bar: the Town menu command (⌘R) that replies to the selected post.",
        )
    }

    /// The composer's placeholder.
    package static func placeholder(townName: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "composer.placeholder",
            defaultValue: "Say something to \(townName)…",
            bundle: .module,
            comment: """
            Composer: the placeholder of the one-line field where you post to the town. \
            The argument is the town's name.
            """,
        )
    }

    /// The counter while 20 or fewer characters remain.
    package static func charactersLeft(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "composer.counter.left",
            defaultValue: "\(count) left",
            bundle: .module,
            comment: """
            Composer: under the field once 20 or fewer characters remain before the \
            limit. The argument is how many characters may still be typed.
            """,
        )
    }

    /// The counter past the limit, beside a warning symbol.
    package static func charactersOver(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "composer.counter.over",
            defaultValue: "\(count) over",
            bundle: .module,
            comment: """
            Composer: under the field, after a warning symbol, when the text is longer \
            than a post may be; Return then does nothing. The argument is how many \
            characters too many there are.
            """,
        )
    }

    /// The chip above the field while replying, cut to one line.
    package static func replyChip(name: String, text: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "composer.reply.chip",
            defaultValue: "Replying to \(name) \"\(text)\"",
            bundle: .module,
            comment: """
            Composer: the chip above the field while you reply, after a reply symbol. \
            The arguments are the name of the post's author and its text, which is cut \
            short to one line.
            """,
        )
    }

    /// What VoiceOver reads for the chip.
    package static func replyReading(name: String, text: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "composer.reply.reading",
            defaultValue: "Replying to \(name): \(text)",
            bundle: .module,
            comment: """
            VoiceOver: the composer's chip while you reply. The arguments are the name \
            of the post's author and its text.
            """,
        )
    }
}
