import SwiftUI
import TownsfolkCore

/// A resident's name in a post header (ux-flows S1, F6): a plain button in `.headline`
/// that opens their profile in a popover anchored to it — on a click, or when Town › Show
/// Profile (⌘I) asks for this post. The popover opens only once the profile has loaded,
/// so a resident who no longer resolves opens nothing. Esc or a click outside closes it,
/// and focus returns to the post.
struct ResidentNameButton: View {
    let name: String
    let postID: Post.ID
    let model: TimelineViewModel
    /// Puts focus back on the post once the popover closes.
    let returnFocus: () -> Void
    @State private var profile: ResidentProfile?

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
            if let profile {
                ProfilePopover(profile: profile)
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
            profile != nil
        } set: { shown in
            if !shown {
                profile = nil
                returnFocus()
            }
        }
    }

    private func open() {
        guard let loading = model.profileModel(for: postID) else {
            return
        }
        Task {
            await loading.load()
            profile = loading.profile
        }
    }
}
