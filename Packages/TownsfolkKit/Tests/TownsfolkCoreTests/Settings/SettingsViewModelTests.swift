import Foundation
import Testing
import TownsfolkCore

/// A name of exactly `count` characters, so a boundary test states its length rather
/// than a literal someone has to count.
private func name(ofLength count: Int) -> String {
    String(repeating: "a", count: count)
}

/// Closing the pane submits a name that was typed but neither returned nor left, and
/// stays silent when nothing was edited.
@MainActor
@Suite("SettingsViewModel, closing the pane")
struct SettingsViewModelClosingTests {
    @Test
    func `closing the pane stores a valid name that was typed but not submitted`() throws {
        try withFreshDefaults { suite in
            suite.defaults.set("Tomo", forKey: StoredKey.displayName)
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameEdited("  Hana ")
            model.paneClosed()
            #expect(suite.stored(StoredKey.displayName) as? String == "Hana")
            #expect(model.displayName?.value == "Hana")
            #expect(model.nameField == "Hana")
            #expect(model.nameError == nil)
        }
    }

    @Test
    func `closing the pane on an invalid typed name keeps the stored name and shows the error`(
    ) throws {
        try withFreshDefaults { suite in
            suite.defaults.set("Tomo", forKey: StoredKey.displayName)
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameEdited("")
            model.paneClosed()
            #expect(suite.stored(StoredKey.displayName) as? String == "Tomo")
            #expect(model.nameError?.resolved(in: .english) == "Use 1–20 characters.")
            #expect(model.nameField.isEmpty)
        }
    }

    @Test(arguments: [
        ("Tomo", "Tomo"),
        ("Tomo", " Tomo "),
        (nil, ""),
        (nil, "   "),
    ] as [(String?, String)])
    func `closing the pane with nothing edited writes nothing and shows no error`(
        stored: String?,
        field: String,
    ) throws {
        try withFreshDefaults { suite in
            if let stored {
                suite.defaults.set(stored, forKey: StoredKey.displayName)
            }
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameEdited(field)
            model.paneClosed()
            #expect(suite.stored(StoredKey.displayName) as? String == stored)
            #expect(model.nameError == nil)
            #expect(model.nameField == field)
        }
    }

    @Test
    func `closing the pane after a rejected name that was put back clears the error`() throws {
        try withFreshDefaults { suite in
            suite.defaults.set("Tomo", forKey: StoredKey.displayName)
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameSubmitted("")
            model.nameEdited("Tomo")
            model.paneClosed()
            #expect(model.nameError == nil)
            #expect(suite.stored(StoredKey.displayName) as? String == "Tomo")
        }
    }

    @Test
    func `the name's length comes from the injected tuning, and so does the error`() throws {
        try withFreshDefaults { suite in
            var tuning = Tuning.default
            tuning.founding.displayNameLength = 2 ... 3
            let model = SettingsViewModel(defaults: suite.defaults, tuning: tuning)
            model.nameSubmitted("A")
            #expect(model.nameError?.resolved(in: .english) == "Use 2–3 characters.")
            #expect(model.displayName == nil)
            model.nameSubmitted("Abc")
            #expect(model.nameError == nil)
            #expect(model.displayName?.value == "Abc")
            model.nameSubmitted("Abcd")
            #expect(model.nameError?.resolved(in: .english) == "Use 2–3 characters.")
            #expect(model.displayName?.value == "Abc")
        }
    }
}

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    // MARK: Reading

    @Test
    func `a first open shows no name, Normal, and keeps moving on`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            #expect(model.displayName == nil)
            #expect(model.nameField.isEmpty)
            #expect(model.nameError == nil)
            #expect(model.speed == .normal)
            #expect(model.speedHint.resolved(in: .english) == "About one new post every 3 minutes.")
            #expect(model.keepsMovingInOtherApps == true)
        }
    }

    @Test
    func `opening reads every stored setting, and writes none`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set("Tomo", forKey: StoredKey.displayName)
            defaults.set("fast", forKey: StoredKey.speed)
            defaults.set(false, forKey: StoredKey.keepsMovingInOtherApps)
            let model = SettingsViewModel(defaults: defaults)
            #expect(model.displayName?.value == "Tomo")
            #expect(model.nameField == "Tomo")
            #expect(model.speed == .fast)
            #expect(model.keepsMovingInOtherApps == false)
        }
    }

    // MARK: Your name

    @Test(arguments: [
        ("  A  ", "A"),
        ("Tomo the Baker", "Tomo the Baker"),
        (name(ofLength: 20), name(ofLength: 20)),
        (" \(name(ofLength: 20)) ", name(ofLength: 20)),
    ])
    func `a valid name is stored trimmed at once`(input: String, stored: String) throws {
        try withFreshDefaults { suite in
            suite.defaults.set("Tomo", forKey: StoredKey.displayName)
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameEdited(input)
            model.nameSubmitted(input)
            #expect(suite.stored(StoredKey.displayName) as? String == stored)
            #expect(model.displayName?.value == stored)
            #expect(model.nameField == stored)
            #expect(model.nameError == nil)
        }
    }

    @Test(arguments: [
        "",
        "   ",
        name(ofLength: 21),
        "Tomoyuki the Wandering Baker",
    ])
    func `an invalid name shows the error, keeps the stored name, and keeps the input`(
        input: String,
    ) throws {
        try withFreshDefaults { suite in
            suite.defaults.set("Tomo", forKey: StoredKey.displayName)
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameEdited(input)
            model.nameSubmitted(input)
            #expect(model.nameError?.resolved(in: .english) == "Use 1–20 characters.")
            #expect(suite.stored(StoredKey.displayName) as? String == "Tomo")
            #expect(model.displayName?.value == "Tomo")
            #expect(model.nameField == input)
        }
    }

    @Test
    func `a valid name after an error clears the error`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameSubmitted(name(ofLength: 21))
            #expect(model.nameError != nil)
            model.nameSubmitted("Tomo")
            #expect(model.nameError == nil)
            #expect(model.displayName?.value == "Tomo")
            #expect(suite.stored(StoredKey.displayName) as? String == "Tomo")
        }
    }

    @Test
    func `submitting the stored name again writes nothing and clears an error`() throws {
        try withFreshDefaults { suite in
            // Stored untrimmed by hand, so a write of the trimmed name would show.
            suite.defaults.set(" Tomo ", forKey: StoredKey.displayName)
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameSubmitted("")
            #expect(model.nameError != nil)
            model.nameSubmitted("Tomo ")
            #expect(suite.stored(StoredKey.displayName) as? String == " Tomo ")
            #expect(model.nameError == nil)
            #expect(model.nameField == "Tomo")
        }
    }

    @Test
    func `editing the name changes only the field`() throws {
        try withFreshDefaults { suite in
            suite.defaults.set("Tomo", forKey: StoredKey.displayName)
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameSubmitted("")
            model.nameEdited("Tom")
            #expect(model.nameField == "Tom")
            #expect(model.nameError != nil)
            #expect(model.displayName?.value == "Tomo")
            #expect(suite.stored(StoredKey.displayName) as? String == "Tomo")
        }
    }

    @Test
    func `a first name is stored when none was before`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            model.nameSubmitted("Tomo")
            #expect(suite.stored(StoredKey.displayName) as? String == "Tomo")
            #expect(model.displayName?.value == "Tomo")
        }
    }

    // MARK: Speed

    @Test(arguments: [
        (Speed.slow, "slow", "About one new post every 15 minutes."),
        (Speed.normal, "normal", "About one new post every 3 minutes."),
        (Speed.fast, "fast", "About one new post every 30 seconds."),
    ])
    func `choosing a speed stores it at once and shows its hint`(
        speed: Speed,
        stored: String,
        hint: String,
    ) throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            model.speedChosen(speed)
            #expect(model.speed == speed)
            #expect(suite.stored(StoredKey.speed) as? String == stored)
            #expect(model.speedHint.resolved(in: .english) == hint)
        }
    }

    @Test
    func `the speeds are offered slowest first, each with its name`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            #expect(SettingsViewModel.speedChoices == [.slow, .normal, .fast])
            #expect(SettingsViewModel.speedChoices
                .map { model.speedName($0).resolved(in: .english) } == [
                    "Slow",
                    "Normal",
                    "Fast",
                ])
        }
    }

    // MARK: Keep moving

    @Test
    func `changing keep-moving stores it at once, both ways`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            model.keepsMovingChanged(false)
            #expect(model.keepsMovingInOtherApps == false)
            #expect(suite.stored(StoredKey.keepsMovingInOtherApps) as? Bool == false)
            model.keepsMovingChanged(true)
            #expect(model.keepsMovingInOtherApps == true)
            #expect(suite.stored(StoredKey.keepsMovingInOtherApps) as? Bool == true)
        }
    }

    // MARK: Wording

    @Test
    func `every label and helper reads as the pane shows it`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            #expect(model.nameTitle.resolved(in: .english) == "Your name")
            #expect(model.speedTitle.resolved(in: .english) == "Speed")
            #expect(model.keepsMovingTitle.resolved(in: .english)
                == "Keep the town moving while I use other apps")
            #expect(model.keepsMovingHelp.resolved(in: .english)
                == "When off, the town rests unless its window is active.")
        }
    }
}
