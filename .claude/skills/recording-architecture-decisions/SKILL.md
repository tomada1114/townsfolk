---
name: recording-architecture-decisions
description: >
  Covers the ADR tree under docs/architecture/: its README.md index, adr/template.md,
  and the numbered adr/NNNN-*.md records. Use when a change adds a target or a Core
  port, changes the app shape (LSUIElement, MenuBarExtra), the App Sandbox or an
  entitlement, persistence, a package dependency, distribution (Mac App Store,
  Developer ID, Sparkle), deploymentTarget or platforms:, a TCC permission, or a
  shipped language beyond English (defaultLocalization); when
  proposing, accepting, amending, rejecting, or superseding an ADR; when writing a
  version, an availability, a price, or an Apple policy into a document; or when
  deciding whether a change owes an ADR at all.
---

# Recording Architecture Decisions

**Owns:** `docs/architecture/` — whether a change owes an ADR or a status change, an
ADR's shape, numbering, and statuses, amending versus superseding, keeping the index
true, and how a fact is written into any of it. **Does not own:** which other surface a
change lands on, including `docs/architecture.md` and README's Design Philosophy
(`updating-docs`); how a skill is written (`authoring-skills`); how the choice itself is
made — the app shape and sandbox posture (`starting-an-app`), a system API and its
permission (`integrating-system-apis`), a gate file (`changing-gates`), a dependency
(`.claude/rules/project.md`'s Dependency Policy); the decisions themselves — those are
the ADRs.

## What the tree is for

- `docs/architecture/README.md` is the index: the status legend, how an ADR changes,
  and one row per ADR with its status.
- `docs/architecture/adr/template.md` is the shape every ADR copies.
- `docs/architecture/adr/NNNN-<kebab-case-title>.md` records one decision each.

`docs/architecture.md`, beside the tree, describes the layers every app starts with
(Core, UI, Platform, `App/`). It is not an ADR and takes no status: when an ADR moves a
boundary it describes, the ADR records why and `docs/architecture.md` and `AGENTS.md`'s
Architecture section are updated to describe the result, in the same pull request.

## The template or an app

The template repository ships the index empty, on purpose. Its own reasoning lives in
README's Design Philosophy, and ADRs belong to the apps cut from it. So:

- In the template itself, before `scripts/bootstrap.sh` has renamed it, a change that
  hits a trigger below updates README's Design Philosophy (`updating-docs`), not the
  tree. Never seed the template's index with an ADR.
- In an app, the same change owes an ADR.

## When a change owes an ADR

A decision owes one when it is expensive to reverse, or when someone outside the change
will build on it. `AGENTS.md`'s "Before changing the architecture" names the macOS
triggers; each is here with why it is expensive:

- **A new target or port** — a target in `project.yml` or `Package.swift` fixes a
  dependency direction every later file obeys; a new Core port fixes the contract the
  adapter, the fake, and every consumer are written against.
- **App shape** — windowed or menu-bar agent (`LSUIElement`, `MenuBarExtra`) changes
  `project.yml`, the `App/` scene, and the launch test at once.
- **Sandbox posture** — the App Sandbox on or off, or an entitlement added. It decides
  which APIs work at all and whether the Mac App Store is open to the app.
- **Persistence** — where and in what format state lives (files under Application
  Support, `UserDefaults`, the Keychain, SwiftData, Core Data). Stored data outlives the
  code that wrote it, so a change later is a migration.
- **A new dependency** — a package the app now builds on; the Dependency Policy's
  checklist is the evidence the ADR cites.
- **Distribution** — the Mac App Store, Developer ID with notarization, an in-app
  updater. It constrains the sandbox, the signing setup, and the release workflow.
- **`deploymentTarget`** — the macOS floor in `project.yml`, and `platforms:` in
  `Package.swift` with it. Raising it drops users; every API choice below it assumes it.
- **A TCC permission** — Accessibility, Input Monitoring, Screen Recording, or any other
  privacy grant. Each one is a prompt the user must accept, a way the app can
  half-work, and often a reason the sandbox has to go.
- **A shipped language beyond English** — the template sets `defaultLocalization: "en"`
  and ships one. A second language makes every later string owe a translation and a
  reviewer, and is hard to withdraw once users run the app in it (`localizing-the-app`).

A refactor inside a module, a test, a view within the existing layers, a rename that
crosses no boundary, or a fix that restores what an ADR already says owes none. Saying
so in the pull request is a legitimate outcome, not a skipped step. The test to apply:
if a reviewer a year from now would ask "why is it like this?" and the code cannot
answer, the answer belongs in an ADR.

An ADR records reasoning; it grants nothing. An entitlement, a signing change, or a new
dependency still needs the sign-off `AGENTS.md`'s "Security and human approval" asks
for, whether or not an ADR exists.

## Shape and statuses

- Copy `adr/template.md` to `adr/NNNN-<kebab-case-title>.md` with the next free number.
  Numbers start at `0001` and are never reused, even for a rejected proposal. Keep the
  template's section order; a section with nothing to say says "None.".
- Statuses run **Proposed** (recommended, awaiting the owner) → **Accepted** (the owner
  confirmed it) → **Superseded by ADR-NNNN**, with **Rejected** for a proposal the owner
  declined. A partly settled decision says which part is which ("Accepted: files under
  Application Support. Proposed: the JSON layout.").
- Only the owner accepts or rejects. An agent writes Proposed, names what acceptance
  needs, and edits a Proposed ADR freely until the owner decides.
- An Accepted ADR takes small corrections in place — a re-checked fact, a clarified
  consequence, a follow-up that landed — each recorded as an `Amended YYYY-MM-DD` line
  under the status saying what changed. If the correction would change what was
  decided, it is not small.
- A decision that is replaced gets a new ADR that says what it replaces and why. The old
  one changes only its status line to `Superseded by ADR-NNNN`, with a link forward; its
  body stays as it was, so the reasoning that held at the time is still readable.
- Update `docs/architecture/README.md`'s table in the same change as the ADR — a new
  row, or a changed status.

## Fact discipline

Keep three kinds of statement apart, in every file of the tree:

- **Verified fact** — every external claim carries a primary-source URL and
  "checked YYYY-MM-DD", listed in the ADR's Sources section. Check it against the
  source itself, never from memory: Apple's developer documentation or App Review
  Guidelines for an API, an availability, an entitlement, or a review rule; a package's
  own repository, release page, and `Package.swift` for its version, license, and
  platform floor.
- **Decision or recommendation** — its reason and the alternatives it beat.
- **Unverified** — prefixed `Unverified:` and listed under the ADR's Open questions. It
  leaves that list only by being verified (and cited) or by deleting the claim that
  needed it. Never fill a gap from memory to complete a table.

The facts an ADR here leans on move: the macOS version an API needs, what the App
Sandbox allows, a review guideline, the Developer Program fee, a package's latest
release. A price carries its unit and date; availability and deprecation carry the OS
version and date. An ADR is read by people judging the design, and one confidently wrong
fact costs the credibility of every correct one beside it.

## Public-repository hygiene

Nothing in the tree carries a Team ID, a certificate name, a signing or notarization
credential, an Apple ID, an unannounced product name, a personal name or email, or any
user's data. Call the person who decides "the owner". The rule for signing material is
`.claude/rules/project.md`'s "Local Signing Identity"; the secret rules are `AGENTS.md`'s
"Security and human approval". This is their application to prose.

## Writing

English, per `AGENTS.md`'s "Important Reminders". Spend words on trade-offs and on what
the code cannot say; do not restate it. Name a symbol or a `project.yml` key rather
than a `path:line`, which rots with the next edit. Keep sketches small enough to check
by eye — a protocol, a key layout, an entitlement list — because nothing compiles a
fenced block in a document (`updating-docs`, "Nothing verifies a fenced example").
`typos` spell-checks the tree; nothing formats Markdown, so run `just lint` before
committing.
