import Foundation
import Testing
import TownsfolkCore
import TownsfolkTestSupport

/// The String Catalog plumbing (`Sources/TownsfolkCore/Resources/Localizable.xcstrings`).
///
/// `swift test` builds with SwiftPM's native build system, which copies the catalog into
/// Core's resource bundle uncompiled, so every English string here comes from a
/// resource's `defaultValue`; only `xcodebuild` compiles the catalog into the app. These
/// tests therefore read the sources and the catalog as text and hold them together:
/// every `LocalizedStringResource(…)` call in `Sources/TownsfolkCore` declares an explicit
/// key, a `defaultValue`, and `bundle: .module`; the keys those calls declare are exactly
/// the catalog's and exactly ``everyCase()``'s; and the catalog's English is what Core
/// renders. Without them, a key missing from the catalog still reads correctly in
/// English and simply never translates. A resource made from a bare string literal is
/// outside what the scan sees (``ResourceDeclarationScan``). Every key also carries a
/// translated Japanese value taking the English's arguments (ADR-0007,
/// ``CatalogTranslationCheck``), and the language helper hands each resource the app
/// language's locale.
@MainActor
@Suite("Localization")
struct LocalizationTests {
    /// A resource Core returns, and the arguments its English format takes — a `String`
    /// for `%@`, an `Int` for `%lld`.
    struct Case {
        let resource: LocalizedStringResource
        let arguments: [any CVarArg]
    }

    /// `Sources/TownsfolkCore`, resolved from this file's path.
    static let coreSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/TownsfolkCore")

    /// Every resource Core returns, once per state that picks a different key, with the
    /// arguments its English takes. Adding a key to Core means adding it here: the
    /// source-scan tests fail until this list names every key Core's sources declare.
    static func everyCase() -> [Case] {
        let answered = FrontmostAppViewModel(
            provider: FakeFrontmostAppProvider(answering: [FrontmostApp(name: "Finder")]),
        )
        answered.refresh()
        let unanswered = FrontmostAppViewModel(provider: FakeFrontmostAppProvider(answering: [nil]))
        let nameLength = 1
        let nameLimit = 20
        return [
            Case(resource: answered.label, arguments: ["Finder"]),
            Case(resource: unanswered.label, arguments: []),
            Case(resource: SettingsWording.languageTitle, arguments: []),
            Case(resource: SettingsWording.languageHelp, arguments: []),
            Case(resource: SettingsWording.nameTitle, arguments: []),
            Case(
                resource: SettingsWording.nameError(length: nameLength ... nameLimit),
                arguments: [nameLength, nameLimit],
            ),
            Case(resource: SettingsWording.speedTitle, arguments: []),
            Case(resource: SettingsWording.keepsMovingTitle, arguments: []),
            Case(resource: SettingsWording.keepsMovingHelp, arguments: []),
        ] + Speed.allCases.flatMap { speed in
            [
                Case(resource: SettingsWording.speedName(speed), arguments: []),
                Case(resource: SettingsWording.speedHint(speed), arguments: []),
            ]
        }
    }

    /// `Sources/TownsfolkCore/Resources/Localizable.xcstrings`.
    private static func catalog() throws -> StringCatalog {
        let url = coreSources.appending(path: "Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
    }

    /// A fixture catalog entry with an English value and, when `japanese` is given, a
    /// Japanese one in that state.
    private static func entry(
        english: String,
        japanese: (state: String, value: String)?,
    ) -> [String: Any] {
        var localizations: [String: Any] = [:]
        localizations["en"] = ["stringUnit": ["state": "translated", "value": english]]
        if let japanese {
            localizations["ja"] = ["stringUnit": ["state": japanese.state, "value": japanese.value]]
        }
        return ["localizations": localizations]
    }

    /// The keys the `LocalizedStringResource(…)` calls in Core's sources declare.
    static func declaredKeys() throws -> Set<String> {
        try Set(ResourceDeclarationScan.declarations(inSourcesAt: coreSources).compactMap(\.key))
    }

    @Test
    func `every resource is looked up in Core's resource bundle, not the main bundle`() {
        for testCase in Self.everyCase() {
            let resource = testCase.resource
            guard case let .atURL(url) = resource.bundle else {
                Issue.record("\(resource.key) is not looked up in Core's bundle")
                continue
            }
            #expect(url.pathExtension == "bundle", "\(resource.key)")
            #expect(url != Bundle.main.bundleURL, "\(resource.key)")
        }
    }

    @Test
    func `every resource Core's sources declare has a key, a defaultValue, and bundle module`(
    ) throws {
        let declarations = try ResourceDeclarationScan.declarations(inSourcesAt: Self.coreSources)
        #expect(!declarations.isEmpty, "the scan found no LocalizedStringResource call")
        for declaration in declarations {
            #expect(
                declaration.followsTheConvention,
                "\(declaration.file): LocalizedStringResource(\(declaration.arguments.prefix(60))…)",
            )
        }
    }

    @Test
    func `the catalog holds exactly the keys Core's sources declare`() throws {
        let declared = try Self.declaredKeys()
        let catalogued = try Set(Self.catalog().strings.keys)
        #expect(declared.subtracting(catalogued).isEmpty, "missing from Localizable.xcstrings")
        #expect(
            catalogued.subtracting(declared).isEmpty,
            "in Localizable.xcstrings but declared nowhere",
        )
    }

    @Test
    func `every key Core's sources declare has a case here`() throws {
        let declared = try Self.declaredKeys()
        let covered = Set(Self.everyCase().map(\.resource.key))
        #expect(declared.subtracting(covered).isEmpty, "missing from everyCase()")
        #expect(covered.subtracting(declared).isEmpty, "in everyCase() but declared nowhere")
    }

    @Test
    func `the scan reads a key and the whole call across an interpolation`() throws {
        let source = """
        // LocalizedStringResource("commented.out", defaultValue: "No", bundle: .module)
        LocalizedStringResource("a.key", defaultValue: "Hi \\(f(x)) (1)", bundle: .module)
        LocalizedStringResource(computedKey, bundle: .main)
        """
        let found = ResourceDeclarationScan.declarations(in: source, file: "Fixture.swift")
        try #require(found.count == 2)
        #expect(found[0].key == "a.key")
        #expect(found[0].arguments.hasSuffix("bundle: .module"))
        #expect(found[0].followsTheConvention)
        #expect(found[1].key == nil)
        #expect(!found[1].followsTheConvention)
    }

    @Test
    func `the catalog's English is exactly what Core renders in English`() throws {
        let catalog = try Self.catalog()
        for testCase in Self.everyCase() {
            let key = testCase.resource.key
            let english = try #require(
                catalog.strings[key]?.localizations[catalog.sourceLanguage]?.stringUnit?.value,
                "\(key) has no English value",
            )
            let formatted = String(format: english, arguments: testCase.arguments)
            #expect(formatted == testCase.resource.resolved(in: .english), "\(key)")
        }
    }

    @Test
    func `the catalog and Core's bundle both declare English as the development language`() throws {
        #expect(try Self.catalog().sourceLanguage == "en")
        let resource = try #require(Self.everyCase().first?.resource, "everyCase() is empty")
        guard case let .atURL(url) = resource.bundle else {
            Issue.record("\(resource.key) is not looked up in Core's bundle")
            return
        }
        #expect(Bundle(url: url)?.developmentLocalization == "en")
    }

    @Test
    func `every catalog key has a translated Japanese value taking the English's arguments`(
    ) throws {
        for problem in try CatalogTranslationCheck.problems(in: Self.catalog(), language: "ja") {
            Issue.record("\(problem)")
        }
    }

    @Test
    func `the translation check names each key whose Japanese is missing, empty, untranslated, or mismatched`(
    ) throws {
        let fixture: [String: Any] = [
            "sourceLanguage": "en",
            "strings": [
                "a.complete": Self.entry(
                    english: "%@ has %lld",
                    japanese: ("translated", "%2$lld 件 %1$@"),
                ),
                "b.missing": Self.entry(english: "Hello", japanese: nil),
                "c.empty": Self.entry(english: "Hello", japanese: ("translated", " ")),
                "d.untranslated": Self.entry(english: "Hello", japanese: ("new", "こんにちは")),
                "e.mismatched": Self.entry(english: "Hi %@", japanese: ("translated", "%lld さん")),
                "f.noEntryAtAll": [String: Any](),
            ],
        ]
        let catalog = try JSONDecoder().decode(
            StringCatalog.self,
            from: JSONSerialization.data(withJSONObject: fixture),
        )
        #expect(CatalogTranslationCheck.problems(in: catalog, language: "ja") == [
            "b.missing has no translated ja value",
            "c.empty has no translated ja value",
            "d.untranslated has no translated ja value",
            "e.mismatched's ja value takes %1$lld where its en takes %1$@",
            "f.noEntryAtAll has no translated ja value",
        ])
    }

    @Test(arguments: [
        ("Frontmost: —", [:]),
        ("100%% sure", [:]),
        ("%@ wrote %lld", [1: "@", 2: "lld"]),
        ("%2$lld件 %1$@", [1: "@", 2: "lld"]),
        ("%d and %ld", [1: "d", 2: "ld"]),
    ] as [(String, [Int: String])])
    func `format specifiers are read by the argument they consume`(
        format: String,
        expected: [Int: String],
    ) {
        #expect(CatalogTranslationCheck.formatSpecifiers(in: format) == expected)
    }

    @Test(arguments: [
        (TownLanguage.english, "en"),
        (TownLanguage.japanese, "ja"),
    ])
    func `the language helper sets every resource's locale to the app language's`(
        language: TownLanguage,
        code: String,
    ) {
        for testCase in Self.everyCase() {
            let localized = language.localized(testCase.resource)
            #expect(localized.locale == Locale(identifier: code), "\(testCase.resource.key)")
            #expect(localized.key == testCase.resource.key)
            #expect(localized.bundleURL != nil, "\(testCase.resource.key)")
            #expect(localized.bundleURL == testCase.resource.bundleURL, "\(testCase.resource.key)")
        }
    }
}

extension Locale {
    /// The catalog's source language. Expectations resolve in it explicitly, so a test's
    /// expected string does not depend on the language of the Mac running it.
    static let english = Locale(identifier: "en")
}

extension LocalizedStringResource {
    /// The bundle this resource is looked up in, when it names one by URL as
    /// `bundle: .module` does; `BundleDescription` itself is not `Equatable`.
    var bundleURL: URL? {
        guard case let .atURL(url) = bundle else {
            return nil
        }
        return url
    }

    /// The string this resource renders as in `locale` — what a view would show a
    /// reader whose language is `locale`.
    func resolved(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }
}
