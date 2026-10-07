import SwiftUI
import TownsfolkCore
import TownsfolkUI

/// The Town menu (ux-flows S8): New Post (⌘N), Reply (⌘R), Show Profile (⌘I), and Scroll
/// to Latest (⌘↑), acting on the focused town window's composer and timeline through
/// `FocusedValues.composer` and `FocusedValues.timeline`. Move to Another Town… joins it
/// later.
///
/// Every title is a Core resource. A command is disabled, not hidden, while it cannot
/// act: New Post with no town window focused; Reply with no post selected, which includes
/// focus on an event row (it cannot be selected); Show Profile likewise, and also with
/// your own post selected; Scroll to Latest with the timeline
/// already at its top.
struct TownCommands: Commands {
    @FocusedValue(\.timeline)
    private var timeline
    @FocusedValue(\.composer)
    private var composer

    var body: some Commands {
        CommandMenu(Text(TimelineViewModel.townMenuTitle)) {
            Button(ComposerViewModel.newPostTitle) {
                composer?.newPostChosen()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(composer == nil)
            Button(ComposerViewModel.replyTitle) {
                if let target = timeline?.selectedReplyTarget {
                    composer?.replyChosen(to: target)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(composer == nil || timeline?.selectedReplyTarget == nil)
            Button(ProfileViewModel.showProfileTitle) {
                timeline?.showProfileChosen()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(timeline?.selectedProfileResident == nil)
            Button(TimelineViewModel.scrollToLatestTitle) {
                timeline?.scrollToLatestChosen()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(timeline?.canScrollToLatest != true)
        }
    }
}
