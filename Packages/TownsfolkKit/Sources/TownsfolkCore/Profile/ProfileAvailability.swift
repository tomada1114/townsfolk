import Foundation

/// Whose profile a post offers (ux-flows S8, F6): a resident's post offers its author's;
/// yours offers none, so your name is not a button and Show Profile is disabled on it.
/// An event row is never a post, so it offers none either.
public enum ProfileAvailability {
    /// The resident whose profile `post` offers, or `nil` for no post or a post of yours.
    public static func resident(of post: TimelinePost?) -> Resident.ID? {
        post?.residentID
    }
}

extension TimelineViewModel {
    /// The selected post's author when Show Profile can act on it, or `nil` — which
    /// disables it — with no post selected or your own post selected.
    public var selectedProfileResident: Resident.ID? {
        ProfileAvailability.resident(of: selectedPostID.flatMap(timelinePost(for:)))
    }

    /// Town › Show Profile (⌘I): asks the selected post's row to open its author's
    /// profile. Does nothing while ``selectedProfileResident`` is `nil`.
    public func showProfileChosen() {
        guard let postID = selectedPostID, selectedProfileResident != nil else {
            return
        }
        profileRequest = ProfileRequest(serial: (profileRequest?.serial ?? 0) + 1, postID: postID)
    }

    /// A profile of the author of post `id`, not loaded yet — or `nil` for a post of
    /// yours, a post the rows do not show, or a timeline with no store behind it.
    public func profileModel(for id: Post.ID) -> ProfileViewModel? {
        guard let store,
              let resident = ProfileAvailability.resident(of: timelinePost(for: id))
        else {
            return nil
        }
        return ProfileViewModel(
            store: store,
            resident: resident,
            locale: environment.locale,
            calendar: environment.calendar,
        )
    }

    /// Opens the profile of post `id`'s author once it has loaded. Only the latest ask
    /// opens: a read that finishes after a newer one began is dropped, so overlapping
    /// clicks never leave a stale or second popover. Nothing opens for a resident who no
    /// longer resolves.
    public func profileChosen(for id: Post.ID) async {
        let token = beginProfile()
        guard let loading = profileModel(for: id) else {
            return
        }
        await loading.load()
        finishProfile(token, postID: id, profile: loading.profile)
    }

    /// The open profile was closed, by Esc or a click outside; a read still under way is
    /// dropped too.
    public func profileDismissed() {
        profileLoadSerial += 1
        presentedProfile = nil
    }

    /// Starts a profile ask, returning the count its read must still match to open.
    package func beginProfile() -> Int {
        profileLoadSerial += 1
        return profileLoadSerial
    }

    /// Opens `profile` for post `postID` if `token` is still the latest ask.
    package func finishProfile(_ token: Int, postID: Post.ID, profile: ResidentProfile?) {
        guard token == profileLoadSerial else {
            return
        }
        presentedProfile = profile.map { PresentedProfile(postID: postID, profile: $0) }
    }

    private func timelinePost(for id: Post.ID) -> TimelinePost? {
        for case let .group(group) in items {
            if let post = group.posts.first(where: { $0.id == id }) {
                return post
            }
        }
        return nil
    }
}
