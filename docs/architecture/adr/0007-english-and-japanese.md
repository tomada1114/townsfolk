# ADR-0007: English and Japanese, switched inside the app

- **Status:** Accepted 2026-09-30: English and Japanese; the in-app setting as the source
  of truth; Core's strings resolved in the app's language; per-language seed tables;
  translation by the implementing agent. Proposed: how the menus macOS provides follow
  the setting at the next launch, until the running app confirms it.
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

The template ships English alone — `defaultLocalization: "en"` and one String Catalog in
Core (`localizing-the-app`) — and makes a second language an ADR. Townsfolk ships
English and Japanese, English by default (requirements decision log). The language is
chosen in the app, at first run and then in Settings, independent of the Mac's language.
The app's own UI switches at once, the menu items macOS provides (Quit, Edit, …) switch
at the next launch, everything written from then on uses the new language, and what was
already written stays as written (§3.10). Dates, relative times, and numbers follow the
app's language, never the Mac's current locale (`docs/design/ux-guidelines.md` ›
Language and copy). Two tables ship per language: the kinds of events, and the axes
residents are seeded from — occupation, personality, life stage, hobby (§3.1, §3.6).
`AGENTS.md` allows text other than English only as a translated value in a String
Catalog.

## Decision drivers

- The UI switches at once, so strings cannot depend on the process's preferred
  languages, which are fixed at launch.
- Tables that fit each language rather than translate one: a Japanese town gets
  occupations that suit a Japanese town.
- Wording stays in Core, under the coverage floor (`localizing-the-app`).
- The owner's choice to leave translation to the implementing agents.

## Considered options

For switching the UI:

1. **Resolve every Core string in the app language's locale**, through a
   `LocalizedStringResource` built with that `locale:`.
2. **Relaunch on a change** — contradicts "switches at once".

For the seed tables:

1. **One JSON file per language in Core's resources**, with `AGENTS.md`'s exception
   widened to cover them.
2. **Entries in the String Catalog** — no rule change, but every language would carry
   the same entries, translated.
3. **English tables only**, with the model writing in the town's language — no rule
   change, but a Japanese town grows from English-speaking ideas, and §3.1 would change.

For translation: the implementing agent writes and checks it, or the owner reviews or
writes it.

## Decision

- **Languages.** English, the development language and the default, and Japanese. The
  language setting (`settings.language`, ADR-0004) is the source of truth.
- **The UI switches at once.** Core view models build each `LocalizedStringResource`
  with `bundle: .module`, as `localizing-the-app` requires, and with `locale:` set to the
  app language's `Locale`; resolving it selects that language's strings whatever the
  process's preferred languages are. The `locale:` argument of
  `String(localized:defaultValue:table:bundle:locale:comment:)` does not select them and
  is not used for this. The same `Locale` goes to every formatter
  (`designing-core-logic` › Inject locale).
- **The model is told the language** in every call's instructions (ADR-0005).
- **Seed tables** live in `Packages/TownsfolkKit/Sources/TownsfolkCore/Resources/Seeds/`,
  one JSON file per language (`en.json`, `ja.json`), each complete on its own and free to
  differ in its entries. Their keys stay English. An event kind's identifier is stored
  with every event (ADR-0004), so an identifier is never reused or removed; its wording
  may change. Their format and size are settled in use (requirements §6).
- **`AGENTS.md`'s English-only exception** now also covers a value in a seed table other
  than `en.json` (changed with this ADR).
- **Translation.** The implementing agent writes the Japanese in the same pull request
  as the English — UI strings and seed tables alike — and checks it; the owner does not
  review translations as a separate step. Completeness is checked mechanically:
  `LocalizationTests` is extended so that every catalog key has a Japanese value and both
  seed files decode to the same shape.
- **Proposed: the menus macOS provides follow at the next launch** through the app's
  `AppleLanguages` default, which Core writes whenever the setting changes, together with
  whatever the app target needs for macOS to count Japanese among its localizations (an
  app-level `ja.lproj`, or `CFBundleLocalizations`). This part is accepted once the
  running app shows the menus switching.

## Consequences

### Positive

- One setting drives the UI, the formatters, the model, and the seed tables.
- Each language's tables can fit that language.

### Negative

- Every user-facing string and every table entry exists twice, and only the
  completeness check and the agent's own reading guard the Japanese.
- `swift test` copies the String Catalog uncompiled, so no test sees the Japanese a view
  will show; only the running app does.
- A third language means a new seed file and a translation of every string, and a new
  ADR.

### Follow-ups

- The language setting and its switching, the Japanese catalog entries, the seed tables,
  the `LocalizationTests` extension, and the next-launch menus check — issues in the
  backlog.

## Open questions

- Unverified: whether SwiftUI's `Text` resolves a `LocalizedStringResource` with the
  resource's own `locale`. If it does not, Core hands the view the resolved string and the
  view uses `Text(verbatim:)`. The first screen's issue settles it.
- Unverified: that the app's `AppleLanguages` default and an app-level declaration of
  Japanese are what make the menus macOS provides follow the setting at the next launch
  (the Proposed part above).
- Unverified: macOS also offers a per-app language in System Settings (Apple's Mac User
  Guide, <https://support.apple.com/guide/mac-help/mchlddb13d65/mac>, seen in search
  results, not read). How it and the in-app setting interact is left to the settings
  issue.
- Unverified: how `typos` (`just lint`) treats the Japanese values in `ja.json`; checked
  when the file lands.

## Sources

- Experiment on this repository's toolchain (Swift 6.3.2, macOS 27.0), 2026-09-30: in a
  SwiftPM target with `en.lproj` and `ja.lproj` string tables and the process's preferred
  language set to English,
  `String(localized: LocalizedStringResource("greeting", defaultValue: "Hello", locale:
  Locale(identifier: "ja"), bundle: .atURL(Bundle.module.bundleURL)))` returned the
  Japanese string, while `String(localized:defaultValue:table:bundle:locale:comment:)`
  with the same locale returned the English one. It used `.strings` files, not a
  compiled String Catalog.
- <https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md> —
  `developmentLanguage` "Defaults to `en`"; known regions come from the project's
  resources — checked 2026-09-30

## Related

- [ADR-0004](0004-persistence-sqlite-in-core.md) — the language setting's key.
- [ADR-0005](0005-foundation-models-in-core.md) — the language each call writes in.
- [ADR-0008](0008-design-lock.md) — the copy style both languages follow.
