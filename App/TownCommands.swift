import SwiftUI
import TownsfolkCore
import TownsfolkUI

/// The Town menu (ux-flows S8): the timeline's commands, acting on the focused town
/// window's timeline through `FocusedValues.timeline`. It starts with Scroll to Latest
/// (⌘↑); New Post, Reply, Show Profile, and Move to Another Town… join it later.
///
/// Every title is a Core resource. A command is disabled, not hidden, while it cannot
/// act: with no timeline focused, or with the timeline already at its top.
struct TownCommands: Commands {
    @FocusedValue(\.timeline)
    private var timeline

    var body: some Commands {
        CommandMenu(Text(TimelineViewModel.townMenuTitle)) {
            Button(TimelineViewModel.scrollToLatestTitle) {
                timeline?.scrollToLatestChosen()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(timeline?.canScrollToLatest != true)
        }
    }
}
