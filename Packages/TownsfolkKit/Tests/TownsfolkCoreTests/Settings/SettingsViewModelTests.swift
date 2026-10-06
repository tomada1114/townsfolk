import Foundation
import Testing
import TownsfolkCore

/// A name of exactly `count` characters, so a boundary test states its length rather
/// than a literal someone has to count.
private func name(ofLength count: Int) -> String {
    String(repeating: "a", count: count)
}

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    // MARK: Reading

    @Test
    func `a first open shows English, no name, Normal, and keeps moving on`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            #expect(model.language == .english)
            #expect(model.displayName == nil)
            #expect(model.nameField.isEmpty)
            #expect(model.nameError == nil)
            #expect(model.speed == .normal)
            #expect(model.speedHint == "About one new post every 3 minutes.")
            #expect(model.keepsMovingInOtherApps == true)
        }
    }

    @Test
    func `opening reads every stored setting, and writes none`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set("ja", forKey: StoredKey.language)
            defaults.set("Tomo", forKey: StoredKey.displayName)
            defaults.set("fast", forKey: StoredKey.speed)
            defaults.set(false, forKey: StoredKey.keepsMovingInOtherApps)
            let model = SettingsViewModel(defaults: defaults)
            #expect(model.language == .japanese)
            #expect(model.displayName?.value == "Tomo")
            #expect(model.nameField == "Tomo")
            #expect(model.speed == .fast)
            #expect(model.keepsMovingInOtherApps == false)
            #expect(suite.stored(StoredKey.appleLanguages) == nil)
        }
    }

    // MARK: Language

    @Test(arguments: [
        (TownLanguage.japanese, "ja"),
        (TownLanguage.english, "en"),
    ])
    func `choosing a language stores it at once`(language: TownLanguage, code: String) throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            model.languageChosen(language)
            #expect(model.language == language)
            #expect(suite.stored(StoredKey.language) as? String == code)
            #expect(suite.stored(StoredKey.appleLanguages) as? [String] == [code])
        }
    }

    @Test
    func `after choosing Japanese, every string of the pane is set to Japanese`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            let paneCases = LocalizationTests.everyCase().filter { testCase in
                testCase.resource.key.hasPrefix("settings.")
            }
            try #require(!paneCases.isEmpty)
            for testCase in paneCases {
                #expect(model.localized(testCase.resource).locale == Locale(identifier: "en"))
            }
            model.languageChosen(.japanese)
            for testCase in paneCases {
                let localized = model.localized(testCase.resource)
                #expect(localized.locale == Locale(identifier: "ja"), "\(testCase.resource.key)")
                #expect(localized.key == testCase.resource.key)
            }
        }
    }

    @Test
    func `the languages are offered in order, each named in its own language`() {
        #expect(SettingsViewModel.languageChoices == [.english, .japanese])
        #expect(TownLanguage.english.nativeName == "English")
        // "日本語", spelled as escapes: Swift source stays English (AGENTS.md).
        #expect(TownLanguage.japanese.nativeName == "\u{65E5}\u{672C}\u{8A9E}")
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
            #expect(model.nameError == "Use 1–20 characters.")
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

    @Test
    func `the name's length comes from the injected tuning, and so does the error`() throws {
        try withFreshDefaults { suite in
            var tuning = Tuning.default
            tuning.founding.displayNameLength = 2 ... 3
            let model = SettingsViewModel(defaults: suite.defaults, tuning: tuning)
            model.nameSubmitted("A")
            #expect(model.nameError == "Use 2–3 characters.")
            #expect(model.displayName == nil)
            model.nameSubmitted("Abc")
            #expect(model.nameError == nil)
            #expect(model.displayName?.value == "Abc")
            model.nameSubmitted("Abcd")
            #expect(model.nameError == "Use 2–3 characters.")
            #expect(model.displayName?.value == "Abc")
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
            #expect(model.speedHint == hint)
        }
    }

    @Test
    func `the speeds are offered slowest first, each with its name`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            #expect(SettingsViewModel.speedChoices == [.slow, .normal, .fast])
            #expect(SettingsViewModel.speedChoices.map(model.speedName) == [
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
    func `every label and helper reads as the pane shows it in English`() throws {
        try withFreshDefaults { suite in
            let model = SettingsViewModel(defaults: suite.defaults)
            #expect(model.languageTitle == "Language")
            #expect(model.languageHelp == "Menus switch the next time Townsfolk opens.")
            #expect(model.nameTitle == "Your name")
            #expect(model.speedTitle == "Speed")
            #expect(model.keepsMovingTitle == "Keep the town moving while I use other apps")
            #expect(model
                .keepsMovingHelp == "When off, the town rests unless its window is active.")
        }
    }
}
