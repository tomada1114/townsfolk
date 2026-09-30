# ADR-0005: Core speaks to Foundation Models, and the model call is a Platform adapter

- **Status:** Accepted 2026-09-30
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

Every word the town writes comes from Apple's on-device model through the Foundation
Models framework, called directly (requirements §3.11 and the decision log). The rules
around it are fixed: the model writes text only — scenes of 1–3 posts, and the invented
town, residents, and event descriptions — while rules decide timing, speakers, seeds,
events, moves, delays, and catch-up; every call uses structured output under the default
guardrails; a refused call is retried with a different seed up to 2 times, then the turn
is skipped; something refused 3 times in a row is left out of later contexts; the context
budget is read at run time and filled with recent posts first; one call runs at a time;
no call runs while the Mac is too hot; and each call is a fresh session built from the
log and thrown away.

Two constraints decide where this code goes:

- The model does not run under `swift test`, nor — as far as anyone has checked — on a
  CI runner, so Core's tests need a stand-in for the call itself.
- What the model is asked is product behavior: the instructions, the prompt, the output
  schema with its guides, and the budget arithmetic. The template keeps decisions in
  Core, under the coverage floor, and keeps adapters to translation
  (`docs/architecture.md` › Ports and adapters).

`FoundationModels` is not among Core's banned imports (`.swiftlint.yml`'s
`no_ui_import_in_core`, `ArchitectureBoundaryTests`), and it exists on iOS as well as
macOS.

## Decision drivers

- The prompt and the schema under the coverage floor and in CI.
- The model call faked in Core's tests and exercised for real on the owner's Mac.
- One definition of each output type.

## Considered options

1. **Core imports FoundationModels, and a port covers only the call.** Core declares the
   `@Generable` output types and builds the instructions and prompts; a small port
   answers availability, the context size, token counts, and "respond under this
   schema".
2. **Core never imports FoundationModels.** Core has its own value types and a
   domain-level port ("write a scene", "found a town"); the adapter declares `@Generable`
   mirrors and maps them. Core stays framework-free, but every output type exists twice,
   and the guides the model reads sit outside the coverage floor.
3. **The call in Core as well, with no port** — Core's tests could not run without the
   model.

## Decision

**Core owns the conversation with the model.** `TownsfolkCore` imports `FoundationModels`
and declares the `@Generable` type of each call's output — a scene (its posts, each with
speaker, reply target, and text, and its topic tags), a founded town, a new resident, an
event's description — along with the code that builds the instructions and prompts,
names the language to write in, fits the prompt to the budget, and checks what comes
back: a scene naming a speaker who was not chosen is discarded.

**The call itself is a port.** Core declares a `Sendable` protocol, provisionally
`LanguageModelProviding`, that answers:

- availability, as a Core enum: available, Apple Intelligence off, device not eligible,
  or the model still downloading;
- the context size, and the token count of a given instructions-and-prompt pair;
- a response to instructions and a prompt under a generation schema, returned as
  generated content that Core decodes into its own `@Generable` type.

The adapter in `TownsfolkPlatform`, provisionally `SystemLanguageModelProvider`,
translates and nothing more: it uses `SystemLanguageModel.default` with the default
guardrails, opens a fresh `LanguageModelSession` per call and drops it, and maps the
framework's errors to a Core error enum — refused (a guardrail violation or a refusal),
over the context size, unavailable, or other — carrying no prompt or generated text. The
fake in `TownsfolkTestSupport` answers from scripted generated content, so a Core test
decodes exactly what the real model's output would decode into, and one contract suite
runs against both (`just test` for the fake, `just test-local` for the adapter).

**The rules around the call live in Core:** retrying with a new seed, leaving out what
keeps being refused, retrying once with half the posts after an overflow, skipping a
turn, one call at a time, and no call while `ProcessInfo`'s thermal state is serious or
critical — read through an injected closure, so a test sets it.

Option 1 beat option 2 because the schema's guides and field names are part of what the
model is told, the same kind of decision as the prompt, and belong under the floor with
it, defined once; it beat option 3 because the call cannot run in CI.

## Consequences

### Positive

- The prompt, the schema, the budget, and every retry rule are tested in CI against a
  scripted model.
- The adapter is small and mechanical, as the template asks of adapters.
- A new kind of call is a new `@Generable` type and a prompt in Core, with no port
  change.

### Negative

- Core depends on an Apple framework whose API moves every year; an SDK change can break
  Core's build, not only an adapter's.
- No test here measures whether a small model keeps a town lively; that is judged in
  use (requirements §6).
- A model other than the system model — a cloud model for external integrations (Later)
  — would sit behind the port; macOS 27's `LanguageModel` protocol is the first place to
  look. That is a new ADR.

### Follow-ups

- The port, the adapter, the fake, and the contract suite — the template's five pieces
  (`docs/architecture.md` › Ports and adapters) — an issue in the backlog.
- The model-unavailable states and messages (ux-flows S7) read the port's availability,
  checked again whenever the window becomes active.

## Open questions

- Unverified: the context size on macOS 27. Apple's documentation says 4,096 tokens per
  session, and the kickoff research found 8,192 reported for macOS 27. Nothing depends on
  either: the budget is read from `contextSize` at run time.
- Unverified: whether the owner's Mac gets only the smaller on-device model; read at run
  time.
- Unverified: an Apple-documented way to open System Settings at the Apple Intelligence
  pane, for ux-flows S7's "Open System Settings"; none was found. Without one, the
  message names where the setting is instead.
- Unverified: the error cases the macOS 27 SDK declares. The documentation now names
  `LanguageModelError.contextSizeExceeded(_:)`, where the 26.5 SDK has
  `LanguageModelSession.GenerationError.exceededContextWindowSize`; the adapter maps
  whatever the SDK it is built with declares.

## Sources

- The macOS 26.5 SDK's `FoundationModels.swiftinterface` (Xcode 26.5, 17F42) —
  `SystemLanguageModel.Availability` is `.available` or `.unavailable(_:)` with the
  reasons `deviceNotEligible`, `appleIntelligenceNotEnabled`, and `modelNotReady`;
  `Guardrails.default`; `contextSize`; `tokenCount(for:)`; `GenerationError` includes
  `exceededContextWindowSize`, `guardrailViolation`, `unsupportedLanguageOrLocale`,
  `decodingFailure`, `rateLimited`, `concurrentRequests`, and `refusal` — checked
  2026-09-30
- <https://developer.apple.com/documentation/foundationmodels/managing-the-context-window>
  — "Apple's on-device foundation model has a context window of 4096 tokens per
  session"; after reaching it, "the session can no longer process additional requests"
  — checked 2026-09-30
- <https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/guardrails/permissivecontenttransformations>
  — "When you generate responses other than `String`, this mode behaves the same way as
  `default` mode and throws `guardrailViolation` errors." — checked 2026-09-30
- <https://developer.apple.com/documentation/foundationmodels/languagemodel> — "A
  protocol that you use to interface with a model."; macOS 27.0+ — checked 2026-09-30

## Related

- [ADR-0003](0003-macos-27-floor.md) — the OS this is built for.
- [ADR-0004](0004-persistence-sqlite-in-core.md) — the log each call is built from.
- [ADR-0007](0007-english-and-japanese.md) — the language each call writes in.
