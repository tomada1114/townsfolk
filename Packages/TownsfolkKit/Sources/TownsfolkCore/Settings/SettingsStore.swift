import Foundation

/// The four settings ADR-0004 keeps in `UserDefaults` (requirements §3.10), and the
/// `AppleLanguages` default ADR-0007 writes beside the language so the menus macOS
/// provides follow it at the next launch.
///
/// It reads and writes the `UserDefaults` it is handed, so `App/` passes `.standard` and a
/// test its own suite. Reads are tolerant: a key that is absent, of the wrong type, or
/// outside its set of values answers that key's default, and the stored value is left as
/// it is until the next write — a read never writes. The keys and the types of their
/// values are contract (`docs/architecture.md` › What is contract and what is private).
///
/// Not `Sendable`: the SDK does not declare `UserDefaults` so, and a store crossing
/// actors would have to claim it unchecked. Whoever owns one keeps it on its own actor.
public struct SettingsStore {
    private enum Key {
        static let displayName = "settings.displayName"
        static let language = "settings.language"
        static let speed = "settings.speed"
        static let keepsMovingInOtherApps = "settings.keepsMovingInOtherApps"
        /// The one key macOS itself reads: the app's preferred languages.
        static let appleLanguages = "AppleLanguages"
    }

    private let defaults: UserDefaults
    private let tuning: Tuning

    /// Your name in the town, or `nil` before first run has asked for it — and when the
    /// stored text is no longer a valid ``DisplayName``, so a hand-edited value never
    /// reaches the timeline. Setting `nil` removes the stored name.
    public var displayName: DisplayName? {
        get {
            guard let text = defaults.object(forKey: Key.displayName) as? String else {
                return nil
            }
            return try? DisplayName(text, tuning: tuning)
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.value, forKey: Key.displayName)
            } else {
                defaults.removeObject(forKey: Key.displayName)
            }
        }
    }

    /// The language the app speaks and the town writes in; ``TownLanguage/default`` until
    /// one is chosen.
    ///
    /// Every write also stores `AppleLanguages` as that one language, even when it is
    /// unchanged: that default, not this key, is what macOS reads at launch to pick the
    /// language of the menus it provides (ADR-0007), and writing it each time repairs a
    /// value something else changed in between.
    public var language: TownLanguage {
        get {
            (defaults.object(forKey: Key.language) as? String).flatMap(TownLanguage.init(rawValue:))
                ?? .default
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.language)
            defaults.set([newValue.rawValue], forKey: Key.appleLanguages)
        }
    }

    /// How often the town writes a scene; ``Speed/default`` until one is chosen.
    public var speed: Speed {
        get {
            (defaults.object(forKey: Key.speed) as? String)
                .flatMap(Speed.init(rawValue:)) ?? .default
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.speed)
        }
    }

    /// Whether the town keeps moving while another app is in front (requirements §3.7);
    /// `true` until turned off. Read through `object(forKey:)`, since `bool(forKey:)`
    /// answers `false` for an absent key.
    public var keepsMovingInOtherApps: Bool {
        get {
            defaults.object(forKey: Key.keepsMovingInOtherApps) as? Bool ?? true
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.keepsMovingInOtherApps)
        }
    }

    /// The app language's `Locale`, for every formatter — dates, relative times, numbers
    /// follow the app's language, never the Mac's (`designing-core-logic` › Inject locale).
    public var locale: Locale {
        language.locale
    }

    /// Creates a store over `defaults`; a stored name is checked against `tuning`'s
    /// display-name length on every read.
    public init(defaults: UserDefaults, tuning: Tuning = .default) {
        self.defaults = defaults
        self.tuning = tuning
    }
}
