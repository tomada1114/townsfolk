import Foundation
import Observation

/// The Settings pane's state and actions over ``SettingsStore`` (ux-flows S5,
/// requirements §3.10): every change is stored the moment it is made, with no Save
/// button.
///
/// Every string the pane shows is resolved here, in the app's language: each resource is
/// set to it with ``TownLanguage/localized(_:)`` and resolved with `String(localized:)`,
/// and the view renders the result with `Text(verbatim:)` — SwiftUI's `Text` ignores a
/// resource's own locale (ADR-0007 › Amended 2026-10-06). Reading a string after
/// ``languageChosen(_:)`` therefore answers in the new language with no relaunch.
///
/// Settings are not a port, so the view model takes the `UserDefaults` itself, defaulting
/// to `.standard`; a test hands it a suite of its own.
@MainActor
@Observable
public final class SettingsViewModel {
    /// The languages the picker offers, in its order.
    public static let languageChoices = TownLanguage.allCases

    /// The speeds the segmented control offers, slowest first (ux-flows S5).
    public static let speedChoices: [Speed] = [.slow, .normal, .fast]

    /// The language the app speaks and the town writes in.
    public private(set) var language: TownLanguage
    /// Your stored name, or `nil` before one was ever stored.
    public private(set) var displayName: DisplayName?
    /// The text in the name field — what was typed, even when it was rejected, so a
    /// rejected name is corrected rather than retyped.
    public private(set) var nameField: String
    /// How often the town writes a scene.
    public private(set) var speed: Speed
    /// Whether the town keeps moving while another app is in front (requirements §3.7).
    public private(set) var keepsMovingInOtherApps: Bool
    /// Whether the last submitted name was rejected; cleared by the next accepted one.
    private var isNameRejected = false

    private let store: SettingsStore
    private let tuning: Tuning

    // MARK: Wording, in the app language

    /// The language picker's label.
    public var languageTitle: String {
        resolved(SettingsWording.languageTitle)
    }

    /// The helper under the language picker.
    public var languageHelp: String {
        resolved(SettingsWording.languageHelp)
    }

    /// The name field's label.
    public var nameTitle: String {
        resolved(SettingsWording.nameTitle)
    }

    /// The line under the name field, or `nil` unless the last submitted name was
    /// rejected. It names the length ``Tuning`` allows.
    public var nameError: String? {
        guard isNameRejected else {
            return nil
        }
        return resolved(SettingsWording.nameError(length: tuning.founding.displayNameLength))
    }

    /// The speed control's label.
    public var speedTitle: String {
        resolved(SettingsWording.speedTitle)
    }

    /// The helper under the speed control, for the chosen speed.
    public var speedHint: String {
        resolved(SettingsWording.speedHint(speed))
    }

    /// The keep-moving toggle's label.
    public var keepsMovingTitle: String {
        resolved(SettingsWording.keepsMovingTitle)
    }

    /// The helper under the keep-moving toggle.
    public var keepsMovingHelp: String {
        resolved(SettingsWording.keepsMovingHelp)
    }

    /// Creates the pane's model over `defaults`, reading each setting once. Reading
    /// writes nothing.
    public init(defaults: UserDefaults = .standard, tuning: Tuning = .default) {
        let settings = SettingsStore(defaults: defaults, tuning: tuning)
        store = settings
        self.tuning = tuning
        language = settings.language
        displayName = settings.displayName
        nameField = settings.displayName?.value ?? ""
        speed = settings.speed
        keepsMovingInOtherApps = settings.keepsMovingInOtherApps
    }

    // MARK: Actions

    /// Stores `language` at once; every string read after this answers in it.
    public func languageChosen(_ language: TownLanguage) {
        store.language = language
        self.language = language
        AppLog.settings.info("language chosen: \(language.rawValue, privacy: .public)")
    }

    /// Takes what the name field now holds, without checking or storing it — that
    /// waits for ``nameSubmitted(_:)``.
    public func nameEdited(_ text: String) {
        nameField = text
    }

    /// Checks `text` when the field is submitted (Return, or leaving the field). A valid
    /// name is stored trimmed and shown trimmed; one equal to the stored name writes
    /// nothing. An invalid one shows ``nameError``, keeps the stored name, and leaves the
    /// field holding `text`.
    ///
    /// Logs whether the name was taken, never the name (`.claude/rules/swift.md` ›
    /// Logging).
    public func nameSubmitted(_ text: String) {
        nameField = text
        let name: DisplayName
        do {
            name = try DisplayName(text, tuning: tuning)
        } catch {
            isNameRejected = true
            AppLog.settings.info("name submitted: rejected")
            return
        }
        isNameRejected = false
        nameField = name.value
        guard name != displayName else {
            AppLog.settings.debug("name submitted: unchanged")
            return
        }
        store.displayName = name
        displayName = name
        AppLog.settings.info("name submitted: stored")
    }

    /// Submits the name field when the pane closes, since closing the window may end the
    /// field's editing with neither Return nor a focus change, and a typed name would be
    /// lost. A field that holds nothing new — the stored name once trimmed, or blank with
    /// no name stored — is not submitted, so closing never raises the error by itself;
    /// it still clears one left over from a rejected name that was then put back.
    public func paneClosed() {
        let trimmed = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (displayName?.value ?? "") else {
            isNameRejected = false
            return
        }
        nameSubmitted(nameField)
    }

    /// Stores `speed` at once; ``speedHint`` follows it.
    public func speedChosen(_ speed: Speed) {
        store.speed = speed
        self.speed = speed
        AppLog.settings.info("speed chosen: \(speed.rawValue, privacy: .public)")
    }

    /// Stores whether the town keeps moving while another app is in front, at once.
    public func keepsMovingChanged(_ keepsMoving: Bool) {
        store.keepsMovingInOtherApps = keepsMoving
        keepsMovingInOtherApps = keepsMoving
        AppLog.settings.info("keeps moving changed: \(keepsMoving, privacy: .public)")
    }

    // MARK: Resolving

    /// `speed`'s segment in the speed control.
    public func speedName(_ speed: Speed) -> String {
        resolved(SettingsWording.speedName(speed))
    }

    /// `resource` set to the app language — the one step every string above takes, so a
    /// test can see which language they resolve in.
    package func localized(_ resource: LocalizedStringResource) -> LocalizedStringResource {
        language.localized(resource)
    }

    private func resolved(_ resource: LocalizedStringResource) -> String {
        String(localized: localized(resource))
    }
}
