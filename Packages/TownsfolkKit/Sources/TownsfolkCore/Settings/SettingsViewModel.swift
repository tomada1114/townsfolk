import Foundation
import Observation

/// The Settings pane's state and actions over ``SettingsStore`` (ux-flows S5,
/// requirements §3.10): every change is stored the moment it is made, with no Save
/// button.
///
/// Every word the pane shows is a `LocalizedStringResource` from ``SettingsWording``,
/// which the view renders as it is.
///
/// Settings are not a port, so the view model takes the `UserDefaults` itself, defaulting
/// to `.standard`; a test hands it a suite of its own.
@MainActor
@Observable
public final class SettingsViewModel {
    /// The speeds the segmented control offers, slowest first (ux-flows S5).
    public static let speedChoices: [Speed] = [.slow, .normal, .fast]

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

    // MARK: Wording

    /// The name field's label.
    public var nameTitle: LocalizedStringResource {
        SettingsWording.nameTitle
    }

    /// The line under the name field, or `nil` unless the last submitted name was
    /// rejected. It names the length ``Tuning`` allows.
    public var nameError: LocalizedStringResource? {
        guard isNameRejected else {
            return nil
        }
        return SettingsWording.nameError(length: tuning.founding.displayNameLength)
    }

    /// The speed control's label.
    public var speedTitle: LocalizedStringResource {
        SettingsWording.speedTitle
    }

    /// The helper under the speed control, for the chosen speed.
    public var speedHint: LocalizedStringResource {
        SettingsWording.speedHint(speed)
    }

    /// The keep-moving toggle's label.
    public var keepsMovingTitle: LocalizedStringResource {
        SettingsWording.keepsMovingTitle
    }

    /// The helper under the keep-moving toggle.
    public var keepsMovingHelp: LocalizedStringResource {
        SettingsWording.keepsMovingHelp
    }

    /// Creates the pane's model over `defaults`, reading each setting once. Reading
    /// writes nothing.
    public init(defaults: UserDefaults = .standard, tuning: Tuning = .default) {
        let settings = SettingsStore(defaults: defaults, tuning: tuning)
        store = settings
        self.tuning = tuning
        displayName = settings.displayName
        nameField = settings.displayName?.value ?? ""
        speed = settings.speed
        keepsMovingInOtherApps = settings.keepsMovingInOtherApps
    }

    // MARK: Actions

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

    /// `speed`'s segment in the speed control.
    public func speedName(_ speed: Speed) -> LocalizedStringResource {
        SettingsWording.speedName(speed)
    }
}
