import SwiftUI
import TownsfolkCore

/// A resident's name in a post header (ux-flows S1, F6): a plain button in `.headline`
/// that opens their profile in a popover anchored to it — on a click, or when Town › Show
/// Profile (⌘I) asks for this post. The timeline keeps the one open profile, so only the
/// latest choice opens; a resident who no longer resolves opens nothing. Esc or a click
/// outside closes it, and focus returns to the post.
struct ResidentNameButton: View {
    let name: String
    let postID: Post.ID
    let model: TimelineViewModel
    /// Puts focus back on the post once the popover closes.
    let returnFocus: () -> Void

    var body: some View {
        Button {
            open()
        } label: {
            Text(verbatim: name)
                .font(.headline)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityHint(Text(ProfileViewModel.nameButtonHint))
        .accessibilityIdentifier("residentNameButton")
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            if let presented = model.presentedProfile, presented.postID == postID {
                ProfilePopover(profile: presented.profile)
            }
        }
        .onChange(of: model.profileRequest) { _, request in
            if request?.postID == postID {
                open()
            }
        }
    }

    private var isPresented: Binding<Bool> {
        Binding {
            model.presentedProfile?.postID == postID
        } set: { shown in
            if !shown, model.presentedProfile?.postID == postID {
                model.profileDismissed()
                returnFocus()
            }
        }
    }

    private func open() {
        Task {
            await model.profileChosen(for: postID)
        }
    }
}
