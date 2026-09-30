---
name: updating-docs
description: >
  Decides whether a change owes a documentation update and which surface it lands on:
  README.md, AGENTS.md, CONTRIBUTING.md, CHANGELOG.md, docs/architecture.md,
  docs/getting-started.md, docs/adding-ios.md, docs/distribution.md, a skill under
  .agents/skills/, or a /// doc comment in Packages/MyAppKit/Sources. Use when triaging
  whether a pull request needs a document changed or a CHANGELOG entry, when a rule, a
  just recipe, or an architecture boundary moved and it is unclear which file owns it,
  when the quickstart or setup steps drifted, or when deciding that an internal refactor
  needs no documentation change.
---

# Updating Documentation

**Owns:** whether a change owes a documentation update, and which surface it lands on.
**Does not own:** what a `///` comment for a given symbol says (`.claude/rules/swift.md`);
how a skill is authored and mirrored (`authoring-skills`); the wording rules for files
under `docs/` and the top-level Markdown (`.claude/rules/docs.md`).

## Decide on observability, not location

Documentation impact is decided by what a **reader can observe**, not by which directory
the edit began in. An internal refactor and a test-only change need no documentation
change — say so explicitly. Deciding that nothing is needed is a legitimate outcome of
this skill, not a shortcut to be double-checked away.

A reader of this template can observe: what the app does when launched, the `just`
recipes and what they run, the setup steps and pinned toolchain, what a gate accepts or
rejects, how the template is turned into a new app (`scripts/bootstrap.sh`), and how a
release is built and signed. A change to any of those owes a document; a change behind
them does not.

- `README.md` changes when the first ten minutes with a checkout change — the Quickstart
  commands, what "Using This Template" asks you to do, or a documented design decision.
- `CONTRIBUTING.md` changes when setup, the toolchain, or the pull request process
  changes.
- Neither changes for a refactor, a test, a gate or rule that `AGENTS.md` owns, or an
  edit to a skill.

## Purpose per file

Each surface has one job; do not blur them, and do not let one grow a second copy of
another's content.

- `README.md` — the tour: what this template is, the Quickstart, "Using This Template"
  (turning it into a new app and keeping up with template updates), and the Design
  Philosophy that records why each major decision was made. It links to `docs/`,
  `AGENTS.md`, and `CONTRIBUTING.md` instead of repeating them.
- `AGENTS.md` — the agent-facing guide: the Quick Reference command index, "Validating a
  change", the Architecture, the Skills and Rules tables, "Security and human approval",
  "Repository scripts", "Enforcement layers", and the Review Checklist. A changed
  boundary, gate, `just` recipe, or script rule lands here.
- `CONTRIBUTING.md` — local setup, the development workflow (with the commands to run
  without Just), the pull request process, Conventional Commits, and the Changelog
  Policy.
- `CHANGELOG.md` — the canonical, human-curated record of user-facing changes, in Keep a
  Changelog format (`CONTRIBUTING.md`'s "Changelog Policy"). A user-facing change gets an
  entry under `[Unreleased]` in the same pull request that makes it; GitHub's generated
  release notes are supplementary, never a substitute.
- `docs/architecture.md` — the layer diagram, "Where new code goes", and the optional
  dependencies worth reaching for. It covers the same ground as `AGENTS.md`'s
  Architecture section, so a moved boundary updates both in the same pull request.
- `docs/architecture/` — an app's Architecture Decision Records and their index, which
  the template ships empty. `recording-architecture-decisions` owns whether a change
  owes an ADR and how one is written; a moved boundary it records still updates
  `docs/architecture.md` and `AGENTS.md`'s Architecture section to match. Its
  `roadmap.md`, the app's direction and not an ADR, is `steering-the-roadmap`'s.
- `docs/getting-started.md`, `docs/adding-ios.md`, `docs/distribution.md` — single-topic
  how-tos: first setup and everyday commands, the runbook for adding an iOS target, and
  the release, signing, and notarization flow. Each owns its one topic; a change to that
  flow updates that file and nothing else restates it.
- `.agents/skills/<name>/SKILL.md` — the conventions of one kind of change, loaded on
  demand. `authoring-skills` owns how one is written, mirrored, and checked.
- `///` doc comments in `Packages/MyAppKit/Sources/**` — a symbol's contract: the "why",
  not what the signature already says (`.claude/rules/swift.md`). Public API carries one
  (`CONTRIBUTING.md`'s "Code Standards"); this skill owns only whether one is owed.

This repository has both a `CHANGELOG.md` and a `docs/` tree, and both are maintained
surfaces, not leftovers — keep them current rather than folding them into a pull request
description. `.claude/rules/docs.md` holds the mechanical rules that load whenever one of
them, `README.md`, or `CONTRIBUTING.md` is touched: the `[Unreleased]` entry, commands
that match the `justfile`, and keeping README's Design Philosophy in sync with a changed
decision.

## A skill is documentation; editing one is usually not a doc change

Both halves are true and the tension is worth holding. A `SKILL.md` is documentation —
for an agent rather than for a person — so it is held to the same prose rules as the
files above. But maintaining one is not itself user-observable, and it obliges no
README, CONTRIBUTING, or `AGENTS.md` edit.

The one exception is the skill set changing shape: a skill added, renamed, or deleted
has to be recorded in `AGENTS.md`'s Skills table, and widening a skill's subject means
widening its row. `scripts/checks/skills-index-complete.sh` (`just check-harness`)
fails when the table's skill names and the directories under `.agents/skills/` differ,
but not when a row's wording no longer matches what the skill covers.

## The checklist owns the mechanical items

`AGENTS.md`'s "Review Checklist" already carries the items that fire most often — `///`
comments on new public API and a `CHANGELOG.md` entry for a user-facing change — and
`.github/PULL_REQUEST_TEMPLATE.md`'s Checklist asks the author to tick the CHANGELOG and
documentation items. Work from those; this skill does not restate their items and
neither should anything else.

## What belongs in prose

Document non-obvious behavior, architecture decisions, and trade-offs. Do not restate
what the code or the type system already says — the same principle `///` comments follow
in `Packages/MyAppKit/Sources/**`. If a reader could get the fact from the signature or
from running the code, it does not need a sentence here.

## Nothing verifies a fenced example

`.claude/rules/docs.md` asks that code examples be valid Swift or shell and that command
examples match the `justfile`, but no gate in this repository compiles or runs a code
block in a document. The one command check is `scripts/checks/just-recipes-exist.sh`
(`just check-harness`), which fails when `AGENTS.md` names a `just <recipe>` the
`justfile` does not define; nothing checks any other command in any other document. Do
not claim more — a document that promises a gate it does not have is worse than one that
stays silent.

That leaves a discipline instead. Keep a fenced example to something a reader can check
by eye — a command, a path, a short snippet. When the example has to be runnable, put the
runnable thing where a test already calls it — `Packages/MyAppKit/Sources/MyAppCore/`
under `just test`, or a script under `scripts/` with its `scripts/tests/` file — and have
the document point at it rather than copy it.

## Generated trees are off-limits

`.claude/skills/` is a generated mirror of `.agents/skills/` (`scripts/sync-agents.sh`,
run as `just agents-sync`) — never hand-edit it, and never include it in a documentation
sweep. Edit the authored file and re-run the sync; `authoring-skills` owns the rest.
`MyApp.xcodeproj` is generated from `project.yml` the same way and is never documented
as if it were a source file.
