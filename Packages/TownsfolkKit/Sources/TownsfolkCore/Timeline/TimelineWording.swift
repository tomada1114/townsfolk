import Foundation

/// Every word the timeline (ux-flows S1) and the Town menu (S8) show or read aloud, as
/// String Catalog resources. ``TimelineViewModel`` hands each to the view, which renders
/// it as it is.
///
/// Computed, so each read builds a fresh resource; `package`, so `LocalizationTests` can
/// list every key without the app seeing them.
package enum TimelineWording {
    /// A time under a minute old.
    package static var now: LocalizedStringResource {
        LocalizedStringResource(
            "timeline.time.now",
            defaultValue: "now",
            bundle: .module,
            comment: """
            Timeline: the relative time of a post or event less than a minute old, after \
            the name ("Jun · now").
            """,
        )
    }

    /// Your name where none is stored, and how VoiceOver names you.
    package static var you: LocalizedStringResource {
        LocalizedStringResource(
            "timeline.post.you",
            defaultValue: "You",
            bundle: .module,
            comment: "Timeline: the name on your own posts and quotes of them when no name is stored.",
        )
    }

    /// The marker after your name on a post of yours.
    package static var youMarker: LocalizedStringResource {
        LocalizedStringResource(
            "timeline.post.youMarker",
            defaultValue: "(you)",
            bundle: .module,
            comment: """
            Timeline: shown after your own name on your posts, in a lighter color, so they \
            are told apart from the residents'.
            """,
        )
    }

    /// The Town menu's title.
    package static var townMenu: LocalizedStringResource {
        LocalizedStringResource(
            "town.menu.title",
            defaultValue: "Town",
            bundle: .module,
            comment: "Menu bar: the title of the Town menu, which holds the timeline's commands.",
        )
    }

    /// The Town menu's command scrolling the timeline to its newest posts.
    package static var scrollToLatest: LocalizedStringResource {
        LocalizedStringResource(
            "town.menu.scrollToLatest",
            defaultValue: "Scroll to Latest",
            bundle: .module,
            comment: "Menu bar: the Town menu command (⌘↑) that scrolls the timeline to its newest posts.",
        )
    }

    /// What VoiceOver reads for a resident's post.
    package static func postReading(
        name: String,
        time: String,
        text: String,
    ) -> LocalizedStringResource {
        LocalizedStringResource(
            "timeline.post.reading",
            defaultValue: "\(name), \(time): \(text)",
            bundle: .module,
            comment: """
            VoiceOver: a resident's post. The arguments are the resident's name, the \
            relative time ("now", "5m"), and the post's text.
            """,
        )
    }

    /// What VoiceOver reads for a post of yours.
    package static func yourPostReading(time: String, text: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "timeline.post.yourReading",
            defaultValue: "You, \(time): \(text)",
            bundle: .module,
            comment: """
            VoiceOver: one of your own posts. The arguments are the relative time ("now", \
            "5m") and the post's text.
            """,
        )
    }

    /// The one-line quote above a group that replies to an older post.
    package static func quoteLine(name: String, text: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "timeline.quote.line",
            defaultValue: "\(name): \"\(text)\"",
            bundle: .module,
            comment: """
            Timeline: the one-line quote of the older post a conversation replies to, \
            after a reply symbol. The arguments are its author's name and its text, which \
            is cut short to one line.
            """,
        )
    }

    /// What VoiceOver reads for a quote line.
    package static func quoteReading(name: String, text: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "timeline.quote.reading",
            defaultValue: "Replying to \(name): \(text)",
            bundle: .module,
            comment: """
            VoiceOver: the quote of the older post a conversation replies to. The \
            arguments are its author's name and its text.
            """,
        )
    }

    /// What VoiceOver reads for a group: a plural over its post count.
    package static func groupReading(count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "timeline.group.reading",
            defaultValue: "Conversation, \(count) posts",
            bundle: .module,
            comment: "VoiceOver: a conversation of one or more posts. The argument is how many posts it holds.",
        )
    }

    /// What VoiceOver reads for an event row.
    package static func eventReading(text: String, time: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "timeline.event.reading",
            defaultValue: "\(text), \(time)",
            bundle: .module,
            comment: """
            VoiceOver: something that happened in town. The arguments are the event's \
            one-line text and its relative time ("now", "5m").
            """,
        )
    }

    /// The pill counting posts that arrived while you read older ones: a plural.
    package static func newPosts(count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "timeline.newPosts",
            defaultValue: "\(count) new posts",
            bundle: .module,
            comment: """
            Timeline: the button above the posts, after an up-arrow symbol, counting the \
            posts that arrived while you were reading older ones. Clicking it scrolls to \
            the newest. The argument is how many arrived.
            """,
        )
    }

    /// The polite announcement when a resident replies to one of your posts.
    package static func repliedToYou(name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "timeline.announcement.repliedToYou",
            defaultValue: "\(name) replied to you",
            bundle: .module,
            comment: """
            VoiceOver announcement when a resident's post replying to one of yours \
            appears. The argument is the resident's name.
            """,
        )
    }
}
