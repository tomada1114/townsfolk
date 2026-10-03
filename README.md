# Townsfolk

[![CI](https://github.com/tomada1114/townsfolk/actions/workflows/ci.yml/badge.svg)](https://github.com/tomada1114/townsfolk/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/tomada1114/townsfolk/badge)](https://scorecard.dev/viewer/?uri=github.com/tomada1114/townsfolk)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A small fictional town that lives in a window at the edge of your Mac screen. Its
residents — people, text only in this version — post to a shared board shaped like a
small social feed and keep conversations going on their own. You glance at it for a few
seconds while you work, read it like a social app when you have a minute, and now and
then post a line as one of the residents; the town answers over the following minutes,
one resident at a time.

Townsfolk is not a tool: it does not help you work, manage tasks, or answer questions.
It exists to be pleasant to watch. What it will not grow is listed under Non-goals in
[`AGENTS.md`](AGENTS.md) › Product and in
[`docs/product/requirements.md`](docs/product/requirements.md).

- **Requirements:** macOS 27 or later, an Apple silicon Mac, and Apple Intelligence
  turned on.
- **Nothing leaves the Mac:** every word the town writes comes from Apple's on-device
  model through the Foundation Models framework — no server, no API key, no network
  access, no analytics. Your posts and the generated text never reach a log
  ([ADR-0002](docs/architecture/adr/0002-sandbox-posture.md)).
- **Languages:** English and Japanese, chosen inside the app
  ([ADR-0007](docs/architecture/adr/0007-english-and-japanese.md)).
- **Getting it:** this version is not distributed — there is no download and no DMG.
  Build it from source with `just install`, then `just run`
  ([ADR-0009](docs/architecture/adr/0009-not-distributed-yet.md)).

Built from the `tomada1114/macos-app-template` repository.

## Quickstart

Prerequisites: Xcode 27+, [mise](https://mise.jdx.dev/), and
[Just](https://just.systems) (`brew install mise just`).

```bash
git clone https://github.com/tomada1114/townsfolk.git
cd townsfolk
mise trust     # approve mise.toml once — mise refuses untrusted configs
just install   # pinned tools via mise + git hooks + xcodegen generate
just check     # verify-hooks → fmt → lint → test-scripts → check-harness → test → build
just run       # build (Debug) and launch the app
```

## Design Philosophy

Townsfolk inherits these choices from the template it was cut from, and each has a
reason. Townsfolk's own principles and how it sits on these layers are in
[docs/architecture.md › Townsfolk on these layers](docs/architecture.md#townsfolk-on-these-layers).

### Why XcodeGen with a gitignored `.xcodeproj`?

`project.yml` is declarative, diffable, and safely editable by both humans and
AI agents; a raw `pbxproj` is a UUID graph that merge conflicts and agents can
silently corrupt. The generated project is treated like a lockfile-derived
artifact: regenerate, never hand-edit. Trade-off: XcodeGen is a third-party
tool with its own bus factor — but the manifest is simple enough to migrate
away from if that ever matters.

### Why a thin app shell + local Swift package?

`App/` contains only the `@main` entry point and resources. Everything real
lives in `Packages/TownsfolkKit`, so tests run with plain `swift test` — no
simulator, no signing, no Xcode project required. Precedent: pointfreeco's
isowords.

### Why the Core/UI/Platform split and a coverage floor on Core only?

`TownsfolkCore` holds all logic and never imports a UI or OS-integration framework
(SwiftUI, AppKit, UIKit, Cocoa, ApplicationServices, Carbon, ServiceManagement —
a lint rule and a test both enforce it); `TownsfolkUI` holds thin
views; `TownsfolkPlatform` holds the adapters that do talk to the OS, each behind a
protocol Core declares, so a test can substitute a fake and `App/` decides which
implementation the app gets (`docs/architecture.md`). The 80% line-coverage and 75%
function-coverage floors apply to Core only — that is what makes a
strict numeric gate *honest* for a GUI app instead of an invitation to write
meaningless view tests. Note: Swift's llvm-cov has no dependable branch
metric, so the gate uses line coverage, plus function coverage so a Core function
no test calls cannot hide under the line floor.

### Why one String Catalog in Core?

User-facing wording is a decision like any other, so it lives where the
coverage floor sees it: Core view models return `LocalizedStringResource`
(Foundation, not a UI framework), and the one `Localizable.xcstrings` sits in
`TownsfolkCore` beside them. Views render those resources and carry no literal of
their own, because a SwiftUI literal is looked up in the app's main bundle, not
the package's. The template ships English alone — `defaultLocalization: "en"`
and one catalog — since a second language makes every later string owe a
translation and a reviewer, so an app that wants one records it as an ADR. The
`localizing-the-app` skill holds the rules, including one that shapes the
tests: `swift test` copies the catalog uncompiled (only `xcodebuild` compiles
it), so `LocalizationTests` scans Core's sources for `LocalizedStringResource`
calls and checks their keys and English against the catalog's source.
Townsfolk itself ships English and Japanese, switched inside the app:
[ADR-0007](docs/architecture/adr/0007-english-and-japanese.md).

### Why Swift Testing?

`@Test`, `#expect`, and parameterized `@Test(arguments:)` are the modern
default shipped with the toolchain. XCTest appears exactly once — in the
XCUITest launch target, because Apple has not ported UI automation to Swift
Testing.

### Why zero dependencies?

The template does not impose opinions about networking, persistence, or
update frameworks. You add what you need; docs/architecture.md lists vetted
suggestions (ViewInspector, swift-snapshot-testing, Sparkle) and when they
earn their place.

### Why Just?

One command — `just check` — runs the same gate locally that CI runs. Just has
cleaner syntax than Make and is a task runner, not a build system, which is
exactly what an Xcode project needs. Every recipe also works without Just (see
CONTRIBUTING.md).

### Why AGENTS.md and .claude/rules/?

AI-assisted development is the norm, not the exception. `AGENTS.md` and
path-scoped rules give LLMs the project's standards, architecture, and hard
prohibitions (never lower the coverage floor, never disable safety lint
rules) — reducing review cycles.

### Why an ADR tree that ships empty?

The template's own decisions are the ones above. An app makes decisions of a
different kind — its shape, its sandbox posture, where it keeps state, how it
ships, which permissions it asks for — and records each as an Architecture
Decision Record under `docs/architecture/`, whose index the template ships
empty. Townsfolk's decisions are ADR-0001 through ADR-0009, listed in
[docs/architecture/README.md](docs/architecture/README.md). `AGENTS.md`'s
"Before changing the architecture" names the changes that owe one. An accepted
ADR takes small corrections in place, dated; a replaced decision gets a new
ADR rather than a rewrite, so the reasoning that held at the time stays
readable.

### Why secret-gated notarization?

The template's release workflow always produces a DMG; when Developer ID
secrets are configured it signs, notarizes, and staples, otherwise it ad-hoc
signs and says so loudly, so it works without an Apple Developer Program
membership and upgrades to fully trusted distribution by adding secrets — no
workflow edits. See docs/distribution.md. Townsfolk releases nothing yet: no
`v*` tag is pushed, so the workflow never runs, and no secret is configured
([ADR-0009](docs/architecture/adr/0009-not-distributed-yet.md)).

## Keeping up with template updates

A repository generated from a GitHub template has no upstream link — the files
are copied once. The bootstrap script therefore writes `.template-origin`: the
template commit your app was created from on line 1, the template repository on
line 2. To pull later template improvements (CI hardening, lint-rule bumps,
workflow fixes) into your app:

```bash
git remote add template https://github.com/tomada1114/macos-app-template.git
git fetch template
git log --oneline "$(sed -n 1p .template-origin)"..template/main   # what you don't have yet
git cherry-pick <sha>    # or: git merge template/main --allow-unrelated-histories
```

Both lines read `unknown` when the script could not know them honestly: it records
`HEAD` only when the history's root commit is the template's own first commit.
GitHub's "Use this template" gives the new repository a fresh root instead, so its
`HEAD` is not a template commit and its `origin` is your app rather than the template.
The file then names the file tree to look for, so one `git log --format='%H %T'`
over `template/main` finds the commit — fill the two lines in and the command
above works from then on. Update line 1 yourself whenever you adopt template
changes; the script never rewrites an existing file.

Cherry-picking narrowly scoped commits is usually cleaner than a full merge:
the bootstrap rename means most template commits touch files whose names and
contents differ in your repository. Treat the template as a starting point,
not a dependency — adopt the changes that earn their place.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for full setup instructions.

```bash
just install
just check
```

The first local `just uitest` run may prompt for Accessibility permission
(System Settings → Privacy & Security); CI runners are pre-provisioned and
run it on every push. If your app itself asks for such a permission, see
[Keeping Permission Grants Across Rebuilds](docs/getting-started.md#keeping-permission-grants-across-rebuilds) —
ad-hoc-signed Debug builds lose the grant on every rebuild.

## Documentation

- [Requirements](docs/product/requirements.md)
- [UX Flows](docs/product/ux-flows.md)
- [UX Guidelines](docs/design/ux-guidelines.md)
- [Design Direction](docs/design/design-direction.md)
- [Roadmap](docs/architecture/roadmap.md)
- [Getting Started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Architecture Decisions](docs/architecture/README.md)
- [Distribution & Signing](docs/distribution.md)
- [Adding iOS Later](docs/adding-ios.md)

## License

[MIT](LICENSE)
