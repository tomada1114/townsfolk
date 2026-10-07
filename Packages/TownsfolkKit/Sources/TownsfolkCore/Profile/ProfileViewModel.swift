import Foundation
import Observation

/// A resident's profile (ux-flows S4), read once from ``TownStore`` when the popover is
/// asked for and never written. ``profile`` stays `nil` when the resident no longer
/// resolves — the town was moved away — and the popover then does not open.
///
/// The locale and calendar the move date is written in are injected. Nothing about a
/// resident is ever logged (requirements §4).
@MainActor
@Observable
public final class ProfileViewModel {
    /// The Town menu's Show Profile command (⌘I).
    public static var showProfileTitle: LocalizedStringResource {
        ProfileWording.showProfile
    }

    /// VoiceOver's hint on a resident's name: "Show profile".
    public static var nameButtonHint: LocalizedStringResource {
        ProfileWording.nameHint
    }

    /// The hobby row's label.
    public static var hobbyTitle: LocalizedStringResource {
        ProfileWording.hobby
    }

    /// The worry row's label.
    public static var worryTitle: LocalizedStringResource {
        ProfileWording.worry
    }

    /// The relationships row's label.
    public static var knowsTitle: LocalizedStringResource {
        ProfileWording.knows
    }

    /// The interests row's label.
    public static var intoTitle: LocalizedStringResource {
        ProfileWording.into
    }

    /// The profile, or `nil` before ``load()`` and when the resident does not resolve.
    public private(set) var profile: ResidentProfile?
    /// Whether ``load()`` has finished, found or not.
    public private(set) var hasLoaded = false

    @ObservationIgnored private let store: TownStore?
    @ObservationIgnored private let resident: Resident.ID?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let calendar: Calendar

    /// Creates the profile of `resident` over `store`, showing nothing until ``load()``.
    public init(store: TownStore, resident: Resident.ID, locale: Locale, calendar: Calendar) {
        self.store = store
        self.resident = resident
        self.locale = locale
        self.calendar = calendar
    }

    /// Creates a model already showing `profile`, with no store behind it — for a preview.
    package init(profile: ResidentProfile) {
        store = nil
        resident = nil
        locale = .current
        calendar = .current
        self.profile = profile
        hasLoaded = true
    }

    /// Reads the resident, everyone they may know, and the interests that may be shown.
    /// A failed read shows no profile, as a missing resident does.
    public func load() async {
        defer { hasLoaded = true }
        guard let store, let resident else {
            return
        }
        do {
            let residents = try await store.residents()
            guard let found = residents.first(where: { $0.id == resident }) else {
                profile = nil
                return
            }
            let interests = try await store.interests()
            profile = ResidentProfile(
                resident: found,
                residents: residents,
                interests: interests,
                locale: locale,
                calendar: calendar,
            )
        } catch {
            AppLog.timeline
                .error("Reading a profile failed: \(String(describing: error), privacy: .public)")
            profile = nil
        }
    }
}
