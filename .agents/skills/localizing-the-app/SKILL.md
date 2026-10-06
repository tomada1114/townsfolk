---
name: localizing-the-app
description: >
  Covers every string a person reads and its translation, meaning the String Catalog at
  Packages/TownsfolkKit/Sources/TownsfolkCore/Resources/Localizable.xcstrings, defaultLocalization
  in Package.swift, Core view models returning LocalizedStringResource with bundle .module,
  Text(verbatim:) in TownsfolkUI, LocalizationTests, and xcodebuild -exportLocalizations. Use
  when adding or changing user-facing wording, a Text or Button title, a catalog key,
  comment, plural, or translation; when a string shows its key, reads right in English but
  never translates, or a catalog key goes stale; or when an app considers a second
  language.
---

# Localizing the App

**Owns:** where user-facing wording lives, how a string is declared so it can be
translated, keeping the String Catalog and the code in step, and what adding a language
involves. **Does not own:** a view model's shape and injecting a `Locale` to format a
number or date (`designing-core-logic`); how a view is wired to its model
(`building-swiftui-screens`); capitalization and voice (`designing-ui`'s copy rules and
design lock); the ADR a second language owes (`recording-architecture-decisions`); the
English-only rule and its one exception (`AGENTS.md`'s "Important Reminders").

## What the template decides

- **English by default.** `Package.swift` sets `defaultLocalization: "en"`, and the one
  catalog's source language is `en`. Shipping a second language is an app's decision,
  recorded as an ADR: every later string then owes a translation, and every translation
  owes a reviewer. This app made it: ADR-0007
  (`docs/architecture/adr/0007-english-and-japanese.md`) ships English and Japanese,
  switched inside the app.
- **Core owns the wording.** A Core view model returns `LocalizedStringResource`
  (Foundation, which Core may import) and a view renders it (how, in
  [In `TownsfolkUI`](#in-townsfolkui)). The wording then sits under
  the coverage floor, where a test asserts it; a Core API that handed out bare keys would
  leave the view to know the key, the bundle, and the fallback, none of it tested.
- **One string catalog, in Core.** `TownsfolkCore` declares `resources: [.process(...)]`
  for it; `TownsfolkUI` has no string catalog. It does carry other resources: this app's
  custom Color Sets live in its `Resources/Colors.xcassets` (ADR-0008, `designing-ui`).

## Declaring a string

`FrontmostAppViewModel.label` is the worked example:

```swift
LocalizedStringResource(
    "frontmostApp.label",
    defaultValue: "Frontmost: \(name)",
    bundle: .module,
    comment: "Footnote naming the application that is frontmost. The argument is that application's name.",
)
```

Every part is there for a reason:

- **`bundle: .module`.** The default, `.main`, is the app bundle, which has no catalog:
  the string would read correctly in English and never translate. `.module` resolves to
  `Bundle.module`, which SwiftPM generates because the target declares a resource.
- **`defaultValue`.** `swift test` (`just test`) builds with SwiftPM's native build
  system, which copies the `.xcstrings` into Core's bundle uncompiled, so the English a
  test sees comes from here. Without it a test would see the key.
- **An explicit key**, `feature.purpose` (`frontmostApp.label`, `frontmostApp.unavailable`),
  not the English text: the English can be polished without re-keying every translation,
  and a key is something a test and a search can name.
- **`comment`** is a translator's only context: where the text appears and what each
  argument is.
- **One whole sentence per state**, with arguments interpolated (`\(name)` becomes `%@`,
  an `Int` becomes `%lld`), never a fixed prefix glued to a swapped-in fragment: a
  translation must be free to reorder the sentence around its arguments.
- **A computed property**, as `FrontmostAppViewModel.label` is, so each read builds the
  resource afresh. Its `locale` defaults to `.current` when it is built; in an app that
  switches language inside the app, as this one does, Core sets it to the app's language
  with `TownLanguage.localized(_:)` before the view sees it (below).
- **No generated symbols.** `xcodebuild` runs `GenerateStringSymbols` over the catalog, but
  SwiftPM's native build does not, so code that names one fails to compile under
  `just test`.

## In `TownsfolkUI`

- A view has no localizable literal. `Text("…")` and `Button("…")` take a
  `LocalizedStringKey` that is looked up in the app's main bundle, not the package's, and
  `-exportLocalizations` exports it under a `TownsfolkUI` strings file that has nowhere to
  ship. Render a Core resource instead.
- **How a Core resource is rendered.** With English only, `Text(resource)` would do: the
  process's language and the resource's agree. This app ships a second language, and
  ADR-0007's 2026-10-06 amendment found that SwiftUI's `Text` ignores a resource's own
  `locale` and uses the process's language. So the rule every view here follows: Core
  sets the resource's locale with `TownLanguage.localized(_:)` and resolves it with
  `String(localized:)`, and the view renders the string with
  `Text(verbatim: String(localized: resource))` (or a Core-resolved `String` passed to
  `Text(verbatim:)`), never `Text(resource)`. `Text(resource)` shows the process's
  language when the app's setting is another.
- What is not language is also `Text(verbatim:)`: a number (formatted in Core with an injected
  `Locale` when formatting matters), a glyph (whose `.accessibilityLabel` is still a
  Core resource), and a
  preview's note to the developer.
- Accessibility identifiers are never localized (`building-swiftui-screens`).

## Keeping the catalog in step

- A new or changed key lands in the Core code, `Localizable.xcstrings`, and
  `LocalizationTests.everyCase()` in the same change. The suite scans every
  `LocalizedStringResource(…)` call in `Sources/TownsfolkCore` (`ResourceDeclarationScan`)
  and fails until all three agree: a call without an explicit key, a `defaultValue`, or
  `bundle: .module`; a declared key the catalog or `everyCase()` lacks; a catalog key
  declared nowhere; or catalog English that differs from `defaultValue`. It reads the
  catalog's source, not a compiled bundle, because `swift test` never compiles one.
- The scan is text, not a parser. It does not see a resource made from a bare literal
  (`let title: LocalizedStringResource = "Reset"`, which also lands in the main bundle),
  `String(localized:)`, or anything in `TownsfolkUI` — review catches those.
- Edit the catalog in Xcode's editor, or by hand in the format Xcode writes: two-space
  indent, `" : "` separators, keys sorted, no trailing newline (`.editorconfig`'s
  `[*.xcstrings]` section keeps an editor from fighting that). A key the code uses has a
  `comment` and an `en` `stringUnit` with `"state" : "translated"`, and no
  `extractionState`.
- To find drift, run `just generate`, then
  `xcodebuild -exportLocalizations -project Townsfolk.xcodeproj -localizationPath <dir> -exportLanguage en`.
  It extracts every key from Core's source **and rewrites the catalog in place**: a key
  in code but not in the catalog is added (`"extractionState" : "extracted_with_value"`,
  `"state" : "new"`), and a key no code uses gains `"extractionState" : "stale"`. Review
  that diff like any other; neither `just build` nor `swift build` touches the catalog.

## What each build does with the catalog

Checked on Xcode 26.5 (17F42) with Swift 6.3.2, 2026-09-28:

| | `swift build` / `swift test` (`just test`) | `xcodebuild` (`just build`, the app) |
|---|---|---|
| The catalog in `TownsfolkKit_TownsfolkCore.bundle` | copied as `Localizable.xcstrings`, uncompiled | compiled to `en.lproj/Localizable.strings` |
| Where English comes from at run time | each resource's `defaultValue` | the catalog |

`swift build --build-system swiftbuild` (a preview) compiles the catalog too, but
`scripts/coverage.sh` uses the native build. No gate looks inside the app: after
`just build`, `plutil -p` on that `Localizable.strings` under
`build/dev-derived-data/Build/Products/Debug/Townsfolk.app` shows what shipped.

## Plurals

A count inside a sentence is a plural, not `"\(count) items"`: vary the entry by plural
in Xcode's catalog editor, which stores `variations` instead of a `stringUnit`.
`LocalizationTests` reads `stringUnit` only, so the first plural extends its
`CatalogLocalization` to read `variations` and asserts the `one` and `other` English
forms.

## Adding a language

In an app cut from the template, a second language is an ADR the owner accepts before
any translation lands (`recording-architecture-decisions`): which language, who
translates, and who reviews. Then:

- Add the language in Xcode's catalog editor, or import a translated `.xcloc` with
  `xcodebuild -importLocalizations`. Keys, comments, and the English stay English; the
  translated values are the one non-English text the repository allows.
- Unverified: whether macOS offers the app in that language from the package bundle's
  new `.lproj` alone, or the app target also needs `CFBundleLocalizations` or
  `developmentLanguage` in `project.yml`. Check it in the running app (`running-the-app`)
  and record the answer in the ADR.
- Unverified: how `typos` (`just lint`) treats translated values; the ADR decides whether
  an exclusion is warranted, which is a gate change (`changing-gates`).
