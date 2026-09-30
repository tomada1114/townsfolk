# my-app

[![CI](https://github.com/your-username/my-app/actions/workflows/ci.yml/badge.svg)](https://github.com/your-username/my-app/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/your-username/my-app/badge)](https://scorecard.dev/viewer/?uri=github.com/your-username/my-app)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A strict, supply-chain-hardened GitHub template for open-source macOS apps.
It ships as a working counter app: XcodeGen project, thin app shell over a
local Swift package, Swift Testing suite with an enforced coverage floor, an
XCUITest launch guarantee, and hardened CI — all from the first commit.

Most popular OSS macOS apps ship without CI-gated tests, SECURITY.md,
Dependabot, or pinned actions. This template starts with all of them.

**Starting your own app from this template?** Jump to
[Using This Template](#using-this-template).

## Quickstart

Prerequisites: Xcode 26.5+, [mise](https://mise.jdx.dev/), and
[Just](https://just.systems) (`brew install mise just`).

```bash
git clone https://github.com/your-username/my-app.git
cd my-app
mise trust     # approve mise.toml once — mise refuses untrusted configs
just install   # pinned tools via mise + git hooks + xcodegen generate
just check     # verify-hooks → fmt → lint → test-scripts → check-harness → test → build
open MyApp.xcodeproj
```

## Design Philosophy

Every choice in this template has a reason. If you disagree with a decision,
you know exactly what to change and why it was there in the first place.

### Why XcodeGen with a gitignored `.xcodeproj`?

`project.yml` is declarative, diffable, and safely editable by both humans and
AI agents; a raw `pbxproj` is a UUID graph that merge conflicts and agents can
silently corrupt. The generated project is treated like a lockfile-derived
artifact: regenerate, never hand-edit. Trade-off: XcodeGen is a third-party
tool with its own bus factor — but the manifest is simple enough to migrate
away from if that ever matters.

### Why a thin app shell + local Swift package?

`App/` contains only the `@main` entry point and resources. Everything real
lives in `Packages/MyAppKit`, so tests run with plain `swift test` — no
simulator, no signing, no Xcode project required. Precedent: pointfreeco's
isowords.

### Why the Core/UI/Platform split and a coverage floor on Core only?

`MyAppCore` holds all logic and never imports a UI or OS-integration framework
(SwiftUI, AppKit, UIKit, Cocoa, ApplicationServices, Carbon, ServiceManagement —
a lint rule and a test both enforce it); `MyAppUI` holds thin
views; `MyAppPlatform` holds the adapters that do talk to the OS, each behind a
protocol Core declares, so a test can substitute a fake and `App/` decides which
implementation the app gets (`docs/architecture.md`). The 80% line-coverage and 75%
function-coverage floors apply to Core only — that is what makes a
strict numeric gate *honest* for a GUI app instead of an invitation to write
meaningless view tests. Note: Swift's llvm-cov has no dependable branch
metric, so the gate uses line coverage, plus function coverage so a Core function
no test calls cannot hide under the line floor.

### Why one String Catalog in Core, and English only?

User-facing wording is a decision like any other, so it lives where the
coverage floor sees it: Core view models return `LocalizedStringResource`
(Foundation, not a UI framework), and the one `Localizable.xcstrings` sits in
`MyAppCore` beside them. Views render those resources and carry no literal of
their own, because a SwiftUI literal is looked up in the app's main bundle, not
the package's. The template ships English alone — `defaultLocalization: "en"`
and one catalog — since a second language makes every later string owe a
translation and a reviewer; an app that wants one records it as an ADR. The
`localizing-the-app` skill holds the rules, including one that shapes the
tests: `swift test` copies the catalog uncompiled (only `xcodebuild` compiles
it), so `LocalizationTests` scans Core's sources for `LocalizedStringResource`
calls and checks their keys and English against the catalog's source.

### Why Swift Testing?

`@Test`, `#expect`, and parameterized `@Test(arguments:)` are the modern
default shipped with the toolchain. XCTest appears exactly once — in the
XCUITest launch target, because Apple has not ported UI automation to Swift
Testing.

### Why zero dependencies?

An app template should not impose opinions about networking, persistence, or
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

The template's own decisions are the ones above, and this section is where
they live. An app cut from the template makes decisions of a different kind —
its shape, its sandbox posture, where it keeps state, how it ships, which
permissions it asks for — and records each as an Architecture Decision Record
under `docs/architecture/`, whose index the template ships empty. `AGENTS.md`'s
"Before changing the architecture" names the changes that owe one. An accepted
ADR takes small corrections in place, dated; a replaced decision gets a new
ADR rather than a rewrite, so the reasoning that held at the time stays
readable.

### Why secret-gated notarization?

The release workflow always produces a DMG; when Developer ID secrets are
configured it signs, notarizes, and staples, otherwise it ad-hoc signs and
says so loudly. The template works on day one without an Apple Developer
Program membership, and upgrades to fully trusted distribution by adding
secrets — no workflow edits. See docs/distribution.md.

## Using This Template

1. Click **"Use this template"** on GitHub and clone your new repository
   (the bootstrap script enumerates files with `git ls-files`, so it needs a
   git checkout — a ZIP download must be `git init`-ed first)
2. Run the bootstrap script to rename everything:

   ```bash
   scripts/bootstrap.sh CoolApp \
     --bundle-id-prefix io.example --github-user janedoe \
     --author "Jane Doe" --email jane@example.com
   ```

   <!-- bootstrap:keep-begin -->
   This replaces `MyApp` (and `MyAppKit`/`MyAppCore`/`MyAppUI`), `my-app`,
   `com.example`, `your-username`, `Your Name`, and `you@example.com` across
   all tracked files, renames the matching paths, and regenerates the Xcode
   project. Omitted optional arguments leave their placeholders as-is. This
   paragraph, and the other passages that explain the placeholders, sit between
   keep markers the script never rewrites, so they still read correctly after it runs.
   <!-- bootstrap:keep-end -->
3. Fill in `AGENTS.md`'s `## Product` section: what the app is and who it is
   for, the core interaction, and the **Non-goals** it must not grow — the
   agent instructions have no other in-repo answer to "is this in scope?".
   Delete every `TODO:` marker as you go; `just check` fails while one is left
   (`scripts/checks/product-section-filled.sh`).
   Then fill in the `docs/architecture/roadmap.md` skeleton — the Now, Next,
   and Later outcomes that follow from it (the `steering-the-roadmap` skill);
   nothing checks that page, so its `TODO:` lines stay until you replace them
4. Verify the rename: `just install && just check`
5. Create the label set on the new repository: `just labels`
   (`.github/labels.yml`; issue forms rely on these labels existing)
6. Update `README.md` (this file), `SECURITY.md`, the rest of `AGENTS.md`, and
   `CODE_OF_CONDUCT.md` for your app (the conduct-reporting contact stays
   `you@example.com` if `--email` was omitted, so check it), and review
   `LICENSE`'s copyright line (`CHANGELOG.md` is reset automatically)
7. Replace or remove the example code — the counter and the `FrontmostApp`
   port/adapter — following the checklist in
   [docs/getting-started.md › Removing the example code](docs/getting-started.md#removing-the-example-code);
   keep the Core/UI split and the tests
8. For signed releases, add the secrets listed in docs/distribution.md
9. Optional, repository admin only: once the bootstrap commit is on `main`,
   protect it with `just ruleset` (`.github/rulesets/main.json`; it requires
   pull requests from then on, and needs a paid plan on a private repository)
10. Private repository only, before step 9: delete
    `.github/workflows/scorecard.yml`, `codeql.yml`, and `dependency-review.yml`
    (they need a public repository or GitHub Advanced Security), remove the
    `Attest build provenance` step from `release.yml` unless your plan supports
    attestations on private repositories, and drop the `Dependency Review` context
    from `.github/rulesets/main.json` — otherwise no pull request can merge. Details:
    [private-repository.md](.agents/skills/starting-an-app/references/private-repository.md)

To find any placeholders the script left untouched (the pattern uses `.`
wildcards so the rename cannot rewrite this very command into your new names):

```bash
rg -i "my.?app|com\.example|your.username|Your.Name|you@example"
```

### Keeping up with template updates

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

- [Getting Started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Architecture Decisions](docs/architecture/README.md)
- [Distribution & Signing](docs/distribution.md)
- [Adding iOS Later](docs/adding-ios.md)

## License

[MIT](LICENSE)
