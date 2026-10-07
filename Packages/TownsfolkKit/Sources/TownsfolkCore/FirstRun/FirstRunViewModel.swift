import Foundation
import Observation

/// First run before a town exists (requirements §3.1; ux-flows S2 → S3): your name, the
/// one thing asked, then founding the town with it.
///
/// The name validates as you type (ux-guidelines › Forms and validation): Continue is
/// enabled only for 1–20 characters after trimming, and past the limit "{n} over" shows
/// under the field, which keeps the input as typed. Continue stores the trimmed name as
/// `settings.displayName` and hands it to a ``FoundingViewModel`` — S3, which the view
/// then shows and runs. A name already stored means founding was cut short (the app quit
/// midway keeps the name, requirements.md:148), so first run starts at S3 directly.
///
/// The founding screen comes from the `founding` closure the owner passes in, because it
/// needs the founder and the store, which only the composition root can build. Placing
/// these screens in the window, and S7 in their place while the model is unavailable, is
/// the owner's (#27). Nothing you type is ever logged.
@MainActor
@Observable
public final class FirstRunViewModel {
    /// The text in the name field, exactly as typed.
    public private(set) var nameField: String
    /// S3, once Continue took a name or a stored one was found; `nil` while S2 asks.
    public private(set) var founding: FoundingViewModel?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let tuning: Tuning
    @ObservationIgnored private let makeFounding: @MainActor (DisplayName) -> FoundingViewModel

    // MARK: Wording

    /// S2's heading.
    public var welcome: LocalizedStringResource {
        FirstRunWording.welcome
    }

    /// The question above the name field, and the field's label.
    public var namePrompt: LocalizedStringResource {
        FirstRunWording.namePrompt
    }

    /// The helper under the name field.
    public var nameHelp: LocalizedStringResource {
        FirstRunWording.nameHelp
    }

    /// The one plain line about the machinery (ux-guidelines › Language and copy).
    public var machineryNote: LocalizedStringResource {
        FirstRunWording.machineryNote
    }

    /// The default button's title.
    public var continueTitle: LocalizedStringResource {
        FirstRunWording.continueTitle
    }

    /// "{n} over" while the trimmed name is longer than ``Tuning`` allows; `nil` otherwise,
    /// a blank field included.
    public var overLimit: LocalizedStringResource? {
        let length = nameField.trimmingCharacters(in: .whitespacesAndNewlines).count
        let over = length - tuning.founding.displayNameLength.upperBound
        return over > 0 ? FirstRunWording.over(over) : nil
    }

    /// Whether Continue is enabled: the field holds a valid ``DisplayName``.
    public var canContinue: Bool {
        validName != nil
    }

    private var validName: DisplayName? {
        try? DisplayName(nameField, tuning: tuning)
    }

    /// Creates first run over the settings in `defaults`, reading the stored name once.
    /// Reading writes nothing, and no founding starts until its screen runs it.
    ///
    /// - Parameters:
    ///   - defaults: Where `settings.displayName` is kept — `.standard` in the app, a
    ///     suite of its own in a test.
    ///   - tuning: The display name's length.
    ///   - founding: Makes S3 for a name; called once, when Continue takes the name or a
    ///     stored name is found.
    public init(
        defaults: UserDefaults = .standard,
        tuning: Tuning = .default,
        founding: @escaping @MainActor (DisplayName) -> FoundingViewModel,
    ) {
        let store = SettingsStore(defaults: defaults, tuning: tuning)
        let stored = store.displayName
        settings = store
        self.tuning = tuning
        makeFounding = founding
        nameField = stored?.value ?? ""
        self.founding = stored.map(founding)
    }

    // MARK: Actions

    /// Takes what the name field now holds; ``canContinue`` and ``overLimit`` follow it.
    public func nameEdited(_ text: String) {
        guard founding == nil else {
            return
        }
        nameField = text
    }

    /// Continue, or Return in the field: stores the trimmed name and moves on to S3. An
    /// invalid name changes nothing, and once S3 shows a second press — Return and the
    /// default button can both deliver one — is ignored.
    public func continuePressed() {
        guard founding == nil, let name = validName else {
            return
        }
        settings.displayName = name
        nameField = name.value
        founding = makeFounding(name)
        AppLog.settings.info("first run: name stored")
    }
}
