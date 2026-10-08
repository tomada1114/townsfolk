import Foundation
import Testing
import TownsfolkCore

/// The subset of the String Catalog format these tests read: its source language and,
/// per key, each language's single string. A plural or device-varied entry has
/// `variations` instead of a `stringUnit`.
private struct StringCatalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogEntry]
}

/// One key's entry. An entry keyed by its own English text may carry no `localizations`
/// at all, which decodes as none rather than failing the whole catalog.
private struct CatalogEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case localizations
    }

    let localizations: [String: CatalogLocalization]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localizations = try container.decodeIfPresent(
            [String: CatalogLocalization].self,
            forKey: .localizations,
        ) ?? [:]
    }
}

/// One language's value for a key: a single `stringUnit`, or — for a plural — one per
/// plural form under `variations.plural`.
private struct CatalogLocalization: Decodable {
    struct StringUnit: Decodable {
        let value: String
    }

    struct Variations: Decodable {
        let plural: [String: CatalogLocalization]
    }

    let stringUnit: StringUnit?
    let variations: Variations?

    /// The plural form `form` ("one", "other") reads in, or `nil` for a single string.
    func plural(_ form: String) -> String? {
        variations?.plural[form]?.stringUnit?.value
    }

    /// The value a resource formatted with `arguments` reads in English: the single
    /// string, or — for a plural — the form English picks for its first argument.
    func englishValue(for arguments: [any CVarArg]) -> String? {
        if let stringUnit {
            return stringUnit.value
        }
        let count = arguments.first as? Int
        return plural(count == 1 ? "one" : "other")
    }
}

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
/// outside what the scan sees (``ResourceDeclarationScan``).
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
        let nameLength = 1
        let nameLimit = 20
        return [
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
        } + timelineCases() + availabilityCases() + composerCases()
            + firstRunCases()
    }

    /// The first-run screens' resources (S2, S3): each step's line, and its symbol's
    /// label both done and not yet.
    static func firstRunCases() -> [Case] {
        let (over, town) = (3, "Maplewood")
        return [
            Case(resource: FirstRunWording.welcome, arguments: []),
            Case(resource: FirstRunWording.namePrompt, arguments: []),
            Case(resource: FirstRunWording.nameHelp, arguments: []),
            Case(resource: FirstRunWording.machineryNote, arguments: []),
            Case(resource: FirstRunWording.continueTitle, arguments: []),
            Case(resource: FirstRunWording.over(over), arguments: [over]),
            Case(resource: FirstRunWording.foundingHeading, arguments: []),
            Case(resource: FirstRunWording.stepStatus(isDone: true), arguments: []),
            Case(resource: FirstRunWording.stepStatus(isDone: false), arguments: []),
            Case(resource: FirstRunWording.slow, arguments: []),
            Case(resource: FirstRunWording.failed, arguments: []),
            Case(resource: FirstRunWording.tryAgain, arguments: []),
            Case(resource: FirstRunWording.movedTo(town: town), arguments: [town]),
        ] + [FoundingProgress.town, .residents, .firstScene].map { step in
            Case(resource: FirstRunWording.step(step), arguments: [])
        }
    }

    /// The timeline's and the Town menu's resources. A plural is listed with a count of
    /// more than one: under `swift test` a resource renders its `defaultValue`, which is
    /// the `other` form, so the `one` form is held by its own test below.
    static func timelineCases() -> [Case] {
        let (name, time, text) = ("Jun", "1m", "Told you.")
        let count = 3
        return [
            Case(resource: TimelineWording.now, arguments: []),
            Case(resource: TimelineWording.you, arguments: []),
            Case(resource: TimelineWording.youMarker, arguments: []),
            Case(
                resource: TimelineWording.postReading(name: name, time: time, text: text),
                arguments: [name, time, text],
            ),
            Case(
                resource: TimelineWording.yourPostReading(time: time, text: text),
                arguments: [time, text],
            ),
            Case(
                resource: TimelineWording.quoteLine(name: name, text: text),
                arguments: [name, text],
            ),
            Case(
                resource: TimelineWording.quoteReading(name: name, text: text),
                arguments: [name, text],
            ),
            Case(resource: TimelineWording.groupReading(count: count), arguments: [count]),
            Case(
                resource: TimelineWording.eventReading(text: text, time: time),
                arguments: [text, time],
            ),
            Case(resource: TimelineWording.newPosts(count: count), arguments: [count]),
            Case(resource: TimelineWording.repliedToYou(name: name), arguments: [name]),
            Case(resource: TimelineWording.townMenu, arguments: []),
            Case(resource: TimelineWording.scrollToLatest, arguments: []),
        ]
    }

    /// The model-unavailable screen's and banner's resources, and the rows founding and
    /// moves write into the log.
    static func availabilityCases() -> [Case] {
        [ModelAvailability.appleIntelligenceOff, .modelNotReady, .deviceNotEligible]
            .compactMap(AvailabilityWording.message)
            .map { Case(resource: $0, arguments: []) }
            + [Case(resource: AvailabilityWording.openSystemSettings, arguments: [])]
            + [Case(resource: FoundingWording.movedTo(town: "Maplewood"), arguments: ["Maplewood"])]
            + [
                Case(resource: EngineWording.movedIn(name: "Ren"), arguments: ["Ren"]),
                Case(resource: EngineWording.movedAway(name: "Jun"), arguments: ["Jun"]),
            ]
    }

    /// The composer's, the hover Reply button's, and the Town menu's New Post and Reply.
    static func composerCases() -> [Case] {
        let (town, name, text) = ("Maplewood", "Mika", "The oven made a goose noise again.")
        let count = 12
        return [
            Case(resource: ComposerWording.placeholder(townName: town), arguments: [town]),
            Case(resource: ComposerWording.charactersLeft(count), arguments: [count]),
            Case(resource: ComposerWording.charactersOver(count), arguments: [count]),
            Case(
                resource: ComposerWording.replyChip(name: name, text: text),
                arguments: [name, text],
            ),
            Case(
                resource: ComposerWording.replyReading(name: name, text: text),
                arguments: [name, text],
            ),
            Case(resource: ComposerWording.cancelReply, arguments: []),
            Case(resource: ComposerWording.replyButton, arguments: []),
            Case(resource: ComposerWording.newPost, arguments: []),
            Case(resource: ComposerWording.reply, arguments: []),
        ]
    }

    /// `Sources/TownsfolkCore/Resources/Localizable.xcstrings`.
    private static func catalog() throws -> StringCatalog {
        let url = coreSources.appending(path: "Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
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
            let localization = catalog.strings[key]?.localizations[catalog.sourceLanguage]
            let english = try #require(
                localization?.englishValue(for: testCase.arguments),
                "\(key) has no English value",
            )
            let formatted = String(format: english, arguments: testCase.arguments)
            #expect(formatted == testCase.resource.resolved(in: .english), "\(key)")
        }
    }

    @Test(arguments: [
        ("timeline.newPosts", 1, "1 new post", 2, "2 new posts"),
        ("timeline.group.reading", 1, "Conversation, 1 post", 2, "Conversation, 2 posts"),
    ])
    func `a plural entry holds the English one and other forms`(
        key: String,
        one: Int,
        oneReads: String,
        other: Int,
        otherReads: String,
    ) throws {
        let english = try #require(try Self.catalog().strings[key]?.localizations["en"])
        let oneForm = try #require(english.plural("one"), "\(key) has no one form")
        let otherForm = try #require(english.plural("other"), "\(key) has no other form")
        #expect(String(format: oneForm, one) == oneReads)
        #expect(String(format: otherForm, other) == otherReads)
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
}

extension Locale {
    /// The catalog's source language. Expectations resolve in it explicitly, so a test's
    /// expected string does not depend on the language of the Mac running it.
    static let english = Locale(identifier: "en")
}

extension LocalizedStringResource {
    /// The string this resource renders as in `locale` — what a view would show a
    /// reader whose language is `locale`.
    func resolved(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }
}
