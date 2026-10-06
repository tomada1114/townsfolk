---
name: starting-an-app
description: >
  Covers turning this template into a new application with scripts/bootstrap.sh: its
  arguments, the placeholder literals it replaces across git-tracked files, re-running
  it safely, the leftover check, what the new repository keeps untouched, and choosing
  the app's shape - a windowed app or a menu-bar agent (LSUIElement, MenuBarExtra, a
  launch test with no window) - and whether it can stay sandboxed. Use when starting an
  app from this repository, running or editing scripts/bootstrap.sh, a rename left a
  placeholder behind, filling in AGENTS.md's Product section (what the app is, its
  non-goals) or product-section-filled.sh failing,
  deciding whether the new app lives in the Dock or the menu bar,
  whether it must drop the App Sandbox for Accessibility, event taps, or global file
  access, CI's bootstrap-smoke job fails, or setting up a new repository's labels
  (just labels) and branch ruleset (just ruleset).
---

# Starting an App

**Owns:** turning this repository into a new application — the rename
`scripts/bootstrap.sh` performs, the order around it, and what the new app keeps.
**Does not own:** how a skill is authored or mirrored (`authoring-skills`); how a
repository script is written or tested (`writing-repo-scripts`); what a gate file may
contain (`changing-gates`); the README's own prose (`updating-docs`).

<!-- bootstrap:keep-begin -->
This repository ships a bootstrap script on purpose. Its placeholders are a fixed,
small set of literals — `MyApp`, `my-app`, `com.example`, `your-username`, `Your Name`,
and `you@example.com` — with no framework inventory to enumerate, so a single literal
find-and-replace over tracked files is the whole job, and a script does it more
reliably than a checklist would. The script stays in the tree after it runs, so the
record of what it did is a file anyone can still read, and CI's `bootstrap-smoke` job
runs it on a pristine clone on every push, so it cannot silently rot.
<!-- bootstrap:keep-end -->

## The order

Rename first, so nothing downstream is written against the template's identity. Then
write the one thing no literal replace can write — `AGENTS.md`'s `## Product` section —
then verify, then hand-edit the rest of what a replace cannot decide, then set up the
new repository on GitHub. The script prints the list of those steps when it finishes.

## The rename

```bash
scripts/bootstrap.sh CoolApp --bundle-id-prefix io.example --github-user janedoe \
  --author "Jane Doe" --email jane@example.com [--repo cool-app]
```

- **Arguments** (the script's `usage()` prints its header comment). The name is
  required and must be PascalCase. The slug defaults to the kebab-case of the name
  (`--repo` overrides it); the other four options are optional, and an omitted one
  leaves its placeholder in place. A name or slug that itself contains the
  placeholder is refused, because a later run would match it again and corrupt it.
- **The placeholder map** is the six `PH_*` variables at the top of the script. Each
  literal is quote-split there (`'My''App'`) so the replacement never rewrites the
  script's own match sources — a re-run keeps looking for the original placeholders.
- **`replace()`** walks `git ls-files`, so only tracked files are touched: stage a new
  file before running if it should be renamed too. It skips binary and empty files and
  leaves a file without a match untouched. This is why the script refuses to run
  outside a git checkout (**BACKGROUND:** `writing-repo-scripts`).
- **Keep markers:** a line containing the keep-begin marker (the text `bootstrap:keep-`
  followed by `begin`) through the next line containing the keep-end marker is never
  rewritten. The passages that explain the placeholders — the script's header and this
  skill's opening and
  path-rename bullet — are wrapped in them (an HTML comment in Markdown, a `#` comment
  in shell), so they still name the placeholders after the rename. CI's
  `bootstrap-smoke` asserts they survive, and its leftover check ignores kept lines.
<!-- bootstrap:keep-begin -->
- **Paths** named after the app (`MyAppKit`, `MyAppCore`, …) are renamed deepest-first,
  skipping `.git/` and build output, and the Xcode project is regenerated.
<!-- bootstrap:keep-end -->
- **`.template-origin`** records where the app was cut from: the template commit on
  line 1, its repository on line 2, then comment lines. It is written only when the
  file is absent — a re-run, and any hand-edit made after adopting template changes,
  survives — and `replace()` skips it so the rename cannot rewrite the URL. `HEAD` is
  recorded only when the history's root commit is the template's first commit (the
  script carries that SHA); otherwise — a "Use this template" repository, whose fresh
  root the template has never seen, or a shallow clone — both values are `unknown` and
  the file names the tree to search for rather than a SHA `git log <sha>..template/main`
  would reject. `README.md`'s
  "Keeping up with template updates" is the reader-facing half.
- **`CHANGELOG.md`** is reset to a one-entry history for the new project, guarded by a
  marker line so a re-run never wipes the new app's own entries.
- **`SECURITY.md`** loses its template-only passages — each block between a
  `bootstrap:template-only-begin` and a `bootstrap:template-only-end` HTML-comment
  line, markers included — guarded by their presence, so a re-run is a no-op.
- **Template-only CI job:** `bootstrap-smoke` and its `Template Bootstrap Smoke`
  required check in `.github/rulesets/main.json` are removed together, guarded by
  their presence. If either is in a shape the script cannot delete (the ruleset entry
  not one comma-terminated line), it stops with an error naming both files.
- **Idempotent:** running it again with the same name is a no-op.

When it finishes, it prints next steps, including a leftover check: an `rg -i` over the
app name, slug, bundle-id, and GitHub-user placeholders. Anything it still finds is
either an optional argument you omitted or a string written in a shape the literal
replace cannot see — fix those by hand. `README.md`'s own leftover command spells the placeholders with `.` wildcards
for the same reason the script quote-splits them.

Changing the script means keeping `bootstrap-smoke` green: it bootstraps a clone as
`ClaudeUsageBar` (long enough to cross SwiftFormat's max width), asserts no placeholder
survives outside the kept passages, asserts those passages still name the
placeholders, asserts the `CHANGELOG.md` reset, asserts `SECURITY.md` no longer says
"created from this template", asserts `.template-origin` holds a 40-hex commit SHA and
a repository line, asserts the template-only job was retired (and re-runs
`scripts/tests/apply-ruleset_test.sh` in the clone), asserts
`product-section-filled.sh` now *fails* on the renamed tree — the smoke proves the
check fires rather than inventing a product for the clone — then runs
`scripts/lint.sh`, `swift test`, and an `xcodebuild` on the renamed tree. Its
leftover grep is case-insensitive and allows a missing hyphen, so a new mention of the
app name in a spelling the literal replace does not cover (all lowercase, say) fails
that job.

The rename leaves the example code in place: the template's example screen and its
example port and adapter are illustrations, not the app. Removing or replacing them is one
checklist, `docs/getting-started.md` › "Removing the example code", which both
`README.md` and the script's next steps point to.

## Filling in the Product section

`AGENTS.md`'s `## Product` section is the one part of that file about the application
rather than the harness: what the app is and who it is for, the core interaction, the
**Non-goals**, and where those decisions are recorded. Write it immediately after the
rename, before `just check` and before the first feature — an agent picking up an issue
here has no other in-repo answer to "is this in scope?", and a non-goal nobody wrote
down is one an eager implementer reads as a feature.

`scripts/checks/product-section-filled.sh` (`just check-harness`, so `just check` too)
holds both directions off one signal. While `project.yml` still names the app-name
placeholder this is the template, where the section must stay a `TODO:` skeleton —
filling it in here would hand every app cut afterwards a product description that is
not its own. Once the rename has removed that placeholder, no `TODO:` marker may survive in the
section, and it must still name its non-goals. No check can judge the prose that
replaces a marker; that stays with the person who wrote it.

## Choosing the app shape

The template ships one shape: a regular windowed app. A menu-bar agent — no Dock tile,
`MenuBarExtra` in place of `WindowGroup`, and a launch test with no window to wait for —
is three files' difference, and deciding it before the first feature costs far less than
retrofitting it afterwards. [references/app-shapes.md](references/app-shapes.md) holds
both shapes side by side: the `project.yml` keys, the `App/` entry point, and the
`LaunchTests` assertion each one needs, as code proven against `just build`,
`just uitest`, and `just smoke`, plus what XCUITest can and cannot see of a status item.

## Deciding the sandbox posture

Decide this with the shape, before the first feature. An app that drives other
applications through the Accessibility API, posts `CGEvent`s, installs a global event
tap, or reads files the user never picked through an open panel cannot be sandboxed —
and an unsandboxed app can never ship on the Mac App Store. `App/Townsfolk.entitlements`
ships with `com.apple.security.app-sandbox` on and stays on unless the new app is one
of those.

Turning it off is a change `AGENTS.md`'s "Security and human approval" reserves for a
human: propose the flip and name the capability that forces it, never make it yourself.
`docs/distribution.md`'s "Sandboxed or not" holds the rest — what still works sandboxed,
what stays on either way (Hardened Runtime, Developer ID signing, notarization), and the
`INFOPLIST_KEY_NS…UsageDescription` build settings a TCC-gated API needs in
`project.yml`.

## Recording both decisions

Both steps end in the new app's first two recorded decisions, written after the rename
in a section of `docs/architecture.md` that follows the template's layers (in this app,
"Townsfolk on these layers"): an app shape subsection (windowed or menu-bar agent, and why) and a
sandbox posture subsection (sandboxed or not, naming any capability that forces the
flip). Only the owner decides either; an agent proposes them in the pull request. Every
external claim in them (an App Store rule, an API's sandbox behavior) carries its URL
and checked date (`updating-docs` › "Fact discipline"). The template itself records
neither; they belong to the app.

## What the new app keeps

Everything below is about the repository rather than the application, so it survives
the rename unchanged and is most of what starting from this template buys:

- **The gate set** — the `justfile` recipes and the scripts under `scripts/` they call,
  and `.github/workflows/`. A red run early in a new project is an argument for fixing
  the code, never for deleting the check that found it. `bootstrap-smoke` is the one
  job about the template rather than the app, so `scripts/bootstrap.sh` removes it and
  its ruleset entry, and `just ruleset` then requires only jobs the app runs.
- **The commit-time guard** — `.githooks/pre-commit` and its "Staged guard" section
  (`scripts/check-staged.sh`, with the rules in `scripts/guard/`), the one layer that
  stops a secret-shaped path or credential before it reaches history. It knows nothing
  about the app, so keep it whatever the app becomes.
- **The skills** under `.agents/skills/` and their mirror in `.claude/skills/`. Drop one
  only when the subject it owns actually leaves the repository — this one, for example,
  once the rename has landed. **REQUIRED:** `authoring-skills` for the mirror loop and
  the `AGENTS.md` Skills table row that `just check-harness` requires for every skill.
- **The label taxonomy** — `.github/labels.yml`, created on the new repository by
  `just labels`. Run it early: GitHub silently drops a label that an issue form applies
  when the repository does not have it yet. **BACKGROUND:** `triaging-issues` for what
  the labels mean.
- **The branch ruleset** — `.github/rulesets/main.json`, applied by a repository admin
  with `just ruleset`. "Use this template" does not copy rulesets, so the new
  repository has no protection on `main` until someone runs it; on a private
  repository it needs a paid GitHub plan. Run it last, after the bootstrap commit is on
  `main`: from then on every change needs a pull request whose required checks pass,
  so the check list must name only jobs the new app still runs.
  On a **private repository**, delete the workflows it cannot run and drop their
  required contexts first — **REQUIRED:** `references/private-repository.md`.

Both `just labels` and `just ruleset` write to the live repository, so they need a
human's sign-off (`AGENTS.md`'s "Security and human approval") — for a brand-new
repository, that is its owner deciding to run them.
