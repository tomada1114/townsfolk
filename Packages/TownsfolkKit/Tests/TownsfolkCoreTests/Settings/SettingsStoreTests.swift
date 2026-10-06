import Foundation
import Testing
import TownsfolkCore

/// The keys a test reads and writes by hand. Spelled out here rather than read from the
/// store, so a renamed key — a contract change that resets every user's value — fails.
private enum StoredKey {
    static let displayName = "settings.displayName"
    static let language = "settings.language"
    static let speed = "settings.speed"
    static let keepsMovingInOtherApps = "settings.keepsMovingInOtherApps"
    static let appleLanguages = "AppleLanguages"
}

/// A value written by hand where the store expects another — a property-list value of
/// any type, as a person editing the preferences file or an older build could leave.
enum HandWritten: Sendable, CustomTestStringConvertible {
    case bool(Bool)
    case int(Int)
    case string(String)
    case strings([String])

    var object: Any {
        switch self {
        case let .bool(value):
            value

        case let .int(value):
            value

        case let .string(value):
            value

        case let .strings(value):
            value
        }
    }

    var testDescription: String {
        "\(object)"
    }
}

/// A `UserDefaults` suite one test owns.
private struct FreshSuite {
    let name: String
    let defaults: UserDefaults

    /// What the suite itself holds for `key`. `object(forKey:)` would also answer from
    /// the global domain, which always holds an `AppleLanguages` of its own.
    func stored(_ key: String) -> Any? {
        defaults.persistentDomain(forName: name)?[key]
    }
}

/// Runs `body` against a `UserDefaults` suite of its own, removed afterwards, so tests
/// running in parallel never share a stored value.
private func withFreshDefaults(_ body: (FreshSuite) throws -> Void) throws {
    let name = "SettingsStoreTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    try body(FreshSuite(name: name, defaults: defaults))
}

@Suite("SettingsStore")
struct SettingsStoreTests {
    // MARK: Fresh install

    @Test
    func `a fresh install answers every key's default`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            #expect(store.displayName == nil)
            #expect(store.language == .english)
            #expect(store.speed == .normal)
            #expect(store.keepsMovingInOtherApps == true)
            #expect(store.locale == Locale(identifier: "en"))
        }
    }

    @Test
    func `reading never writes, so a fresh install stays empty`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            _ = (store.displayName, store.language, store.speed, store.keepsMovingInOtherApps)
            for key in [
                StoredKey.displayName, StoredKey.language, StoredKey.speed,
                StoredKey.keepsMovingInOtherApps, StoredKey.appleLanguages,
            ] {
                #expect(suite.stored(key) == nil, "\(key)")
            }
        }
    }

    // MARK: Language

    @Test(arguments: [
        (TownLanguage.english, "en"),
        (TownLanguage.japanese, "ja"),
    ])
    func `writing the language stores its code and AppleLanguages`(
        language: TownLanguage,
        code: String,
    ) throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            store.language = language
            #expect(suite.stored(StoredKey.language) as? String == code)
            #expect(suite.stored(StoredKey.appleLanguages) as? [String] == [code])
            #expect(SettingsStore(defaults: defaults).language == language)
            #expect(store.locale == Locale(identifier: code))
        }
    }

    @Test
    func `writing the same language again still writes AppleLanguages`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            store.language = .japanese
            defaults.set(["en"], forKey: StoredKey.appleLanguages)
            store.language = .japanese
            #expect(suite.stored(StoredKey.appleLanguages) as? [String] == ["ja"])
            #expect(store.language == .japanese)
        }
    }

    @Test
    func `switching language back replaces AppleLanguages rather than appending`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            store.language = .japanese
            store.language = .english
            #expect(suite.stored(StoredKey.appleLanguages) as? [String] == ["en"])
            #expect(store.locale == Locale(identifier: "en"))
        }
    }

    @Test(arguments: [
        .string("fr"),
        .string(""),
        .string("JA"),
        .int(1),
        .strings(["ja"]),
    ] as [HandWritten])
    func `an unknown or mistyped stored language answers English and stays stored`(
        stored: HandWritten,
    ) throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set(stored.object, forKey: StoredKey.language)
            let store = SettingsStore(defaults: defaults)
            #expect(store.language == .english)
            #expect(store.locale == Locale(identifier: "en"))
            #expect(suite.stored(StoredKey.language) != nil)
            #expect(suite.stored(StoredKey.appleLanguages) == nil)
        }
    }

    @Test
    func `an unknown stored language is replaced by the next write`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set("fr", forKey: StoredKey.language)
            let store = SettingsStore(defaults: defaults)
            #expect(suite.stored(StoredKey.language) as? String == "fr")
            store.language = .japanese
            #expect(suite.stored(StoredKey.language) as? String == "ja")
        }
    }

    // MARK: Speed

    @Test(arguments: [
        (Speed.slow, "slow"),
        (Speed.normal, "normal"),
        (Speed.fast, "fast"),
    ])
    func `writing the speed stores its name and reads back`(speed: Speed, stored: String) throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            store.speed = speed
            #expect(suite.stored(StoredKey.speed) as? String == stored)
            #expect(SettingsStore(defaults: defaults).speed == speed)
        }
    }

    @Test(arguments: [
        .string("turbo"),
        .string("Fast"),
        .string(""),
        .int(2),
        .bool(true),
    ] as [HandWritten])
    func `an unknown or mistyped stored speed answers normal and stays stored`(
        stored: HandWritten,
    ) throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set(stored.object, forKey: StoredKey.speed)
            #expect(SettingsStore(defaults: defaults).speed == .normal)
            #expect(suite.stored(StoredKey.speed) != nil)
        }
    }

    @Test
    func `a stored turbo is untouched until the next write`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set("turbo", forKey: StoredKey.speed)
            let store = SettingsStore(defaults: defaults)
            #expect(store.speed == .normal)
            #expect(suite.stored(StoredKey.speed) as? String == "turbo")
            store.speed = .slow
            #expect(suite.stored(StoredKey.speed) as? String == "slow")
        }
    }

    // MARK: Keep moving in other apps

    @Test(arguments: [false, true])
    func `writing keep-moving stores the Bool and reads back`(value: Bool) throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            store.keepsMovingInOtherApps = value
            #expect(suite.stored(StoredKey.keepsMovingInOtherApps) as? Bool == value)
            #expect(SettingsStore(defaults: defaults).keepsMovingInOtherApps == value)
        }
    }

    @Test
    func `an absent keep-moving answers true, not bool(forKey:)'s false`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            #expect(defaults.bool(forKey: StoredKey.keepsMovingInOtherApps) == false)
            #expect(SettingsStore(defaults: defaults).keepsMovingInOtherApps == true)
        }
    }

    @Test
    func `a mistyped stored keep-moving answers true`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set("off", forKey: StoredKey.keepsMovingInOtherApps)
            #expect(SettingsStore(defaults: defaults).keepsMovingInOtherApps == true)
        }
    }

    // MARK: Display name

    @Test(arguments: [
        "A",
        "Abcdefghijklmnopqrst",
        "あいうえおかきくけこさしすせそたちつてと",
    ])
    func `a name at the length limits is stored and read back`(text: String) throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            let name = try DisplayName(text)
            store.displayName = name
            #expect(suite.stored(StoredKey.displayName) as? String == text)
            #expect(SettingsStore(defaults: defaults).displayName == name)
        }
    }

    @Test
    func `a 21-character name cannot be made, so it cannot be written`() {
        #expect(throws: TownValueError.tooLong(.displayName, limit: 20)) {
            try DisplayName(String(repeating: "a", count: 21))
        }
    }

    @Test
    func `a name is stored trimmed`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            store.displayName = try DisplayName("  Mio  ")
            #expect(suite.stored(StoredKey.displayName) as? String == "Mio")
        }
    }

    @Test(arguments: [
        .string(""),
        .string("   "),
        .string(String(repeating: "a", count: 21)),
        .int(42),
    ] as [HandWritten])
    func `an invalid stored name answers absent and stays stored`(stored: HandWritten) throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set(stored.object, forKey: StoredKey.displayName)
            #expect(SettingsStore(defaults: defaults).displayName == nil)
            #expect(suite.stored(StoredKey.displayName) != nil)
        }
    }

    @Test
    func `a stored name is validated with the store's tuning`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            defaults.set("Abcdef", forKey: StoredKey.displayName)
            var tuning = Tuning.default
            tuning.founding.displayNameLength = 1 ... 5
            #expect(SettingsStore(defaults: defaults, tuning: tuning).displayName == nil)
            #expect(SettingsStore(defaults: defaults).displayName?.value == "Abcdef")
        }
    }

    @Test
    func `writing no name removes the stored one`() throws {
        try withFreshDefaults { suite in
            let defaults = suite.defaults
            let store = SettingsStore(defaults: defaults)
            store.displayName = try DisplayName("Mio")
            store.displayName = nil
            #expect(suite.stored(StoredKey.displayName) == nil)
            #expect(store.displayName == nil)
        }
    }
}
