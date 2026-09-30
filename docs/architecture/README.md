# Architecture Decisions

This tree records the decisions an app cut from this template makes on top of the
layers it starts with, one Architecture Decision Record (ADR) per decision, and why each
was made. It is written for anyone reviewing the design — including the owner six months
from now — and assumes no context beyond the repository.

Three places hold the reasoning, and each has one job:

- [`../architecture.md`](../architecture.md) describes the layers every app starts with —
  Core, UI, Platform, and the `App/` shell — and where new code goes. It is the ground
  the ADRs build on, not a record of choices.
- The repository README's [Design Philosophy](../../README.md#design-philosophy) holds
  the template's own reasoning: why XcodeGen, why a local package, why zero
  dependencies. The template ships no ADRs of its own.
- The ADRs below record what the app decided after that: its shape, its sandbox posture,
  where it keeps state, what it depends on, how it ships, and which permissions it asks
  for.

`AGENTS.md`'s "Before changing the architecture" names the changes that owe an ADR;
`recording-architecture-decisions` is the skill that writes one.

Beside the ADRs, [`roadmap.md`](roadmap.md) records the app's direction — which outcomes
come now, next, and later — and links the issues and ADRs each one needs. It is not an
ADR: it takes no status and no number, has no row in the table below, and authorizes
nothing. The template ships it as a skeleton; `steering-the-roadmap` is the skill that
changes it.

## Status legend

| Status | Meaning |
|---|---|
| Proposed | A recommendation with its reasoning, not yet confirmed by the owner. Work may start on it only as an experiment. |
| Accepted | Confirmed by the owner. Work builds on it. |
| Rejected | Declined by the owner. Kept, with its number, for the reasoning. |
| Superseded | Replaced by a later ADR, which it names. Kept for the reasoning, never edited into agreement. |

## How an ADR changes

- A Proposed ADR is a draft: edit it freely until the owner decides.
- It becomes Accepted, or Rejected, when the owner confirms; the change is a one-line
  edit to its status, with the date.
- An Accepted ADR takes small corrections in place — a re-checked fact, a clarified
  consequence, a follow-up that landed — each recorded as an `Amended YYYY-MM-DD` line
  under its status saying what changed. What it decided stays the same.
- A decision that is replaced gets a new ADR. The old one becomes
  `Superseded by ADR-NNNN`, gains a link forward, and is otherwise left as it was.
- Numbers run from `0001` and are never reused, even for a rejected proposal.

## Adding an ADR

1. Copy [`adr/template.md`](adr/template.md) to `adr/NNNN-<kebab-case-title>.md`, using
   the next free number.
2. Fill it in, with status Proposed.
3. Add its row to the table below in the same change.

## Decisions

The template ships this table empty: its own reasoning is in the repository README's
Design Philosophy. The first row is the app's first ADR.

| ADR | Decision | Status |
|---|---|---|
| [0001](adr/0001-app-shape.md) | One window, and closing it quits | Accepted |
| [0002](adr/0002-sandbox-posture.md) | Keep the App Sandbox, and add no entitlement | Accepted |
| [0003](adr/0003-macos-27-floor.md) | macOS 27.0 as the floor | Accepted |
| [0004](adr/0004-persistence-sqlite-in-core.md) | The town in one SQLite file owned by Core, and settings in UserDefaults | Accepted |
| [0005](adr/0005-foundation-models-in-core.md) | Core speaks to Foundation Models, and the model call is a Platform adapter | Accepted |
| [0006](adr/0006-window-presence-port.md) | When the town runs — window presence behind a Core port | Accepted |
| [0007](adr/0007-english-and-japanese.md) | English and Japanese, switched inside the app | Accepted; the menus' next-launch switch Proposed |
| [0008](adr/0008-design-lock.md) | Design lock — one lamp in a quiet street | Accepted |
| [0009](adr/0009-not-distributed-yet.md) | Not distributed in this version | Accepted |
