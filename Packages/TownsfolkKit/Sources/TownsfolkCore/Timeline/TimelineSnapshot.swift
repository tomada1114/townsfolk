import Foundation

/// A timeline's state given whole rather than read from a store, so a `#Preview` and a
/// test can show any state without a database (`building-swiftui-screens` › Previews).
/// A timeline built over one has no store: it never loads a page or follows changes, and
/// only its clock moves it on.
package struct TimelineSnapshot: Sendable {
    /// The town's name, or `nil` before there is a town.
    package var townName: String?
    /// The name of every resident a post or quote is by.
    package var residentNames: [Resident.ID: String] = [:]
    /// The entries as loaded at launch: shown without motion, except those later than
    /// now, which are held back until their time.
    package var entries: [TimelineEntry]
    /// Entries that just arrived at the top and are still fading in.
    package var arrivedLive: [TimelineEntry] = []
    /// Entries that arrived while you were scrolled away: held out of the rows, their
    /// posts counted in the new-posts pill.
    package var arrivedWhileAway: [TimelineEntry] = []
    /// The post selected with the keyboard, if any.
    package var selectedPost: Post.ID?

    /// Creates a snapshot of `entries` loaded at launch, with no town name, nothing
    /// arrived since, and nothing selected; set the rest as a state needs.
    package init(entries: [TimelineEntry]) {
        self.entries = entries
    }
}
