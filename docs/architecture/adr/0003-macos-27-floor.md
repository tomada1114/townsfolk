# ADR-0003: macOS 27.0 as the floor

- **Status:** Accepted 2026-09-30
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

The template targets macOS 14: `deploymentTarget.macOS: "14.0"` in `project.yml` and
`platforms: [.macOS(.v14)]` in `Packages/TownsfolkKit/Package.swift`. Townsfolk writes
every word with Apple's on-device model, which needs an Apple silicon Mac with Apple
Intelligence on, and the requirements set macOS 27 or later. The owner's Mac runs macOS
27.0, and the model the app is tuned against in use is macOS 27's.

No API the MVP calls needs 27. In the macOS 26.5 SDK — Xcode 26.5, which `.xcode-version`
pins today — `SystemLanguageModel`, `LanguageModelSession`, and `@Generable` are macOS
26.0+, `contextSize` is back-deployed to 26.0, and `tokenCount(for:)` is 26.4+. The
floor is a statement of what is supported — the OS the app is used and tested on — not
an API requirement.

The toolchain and CI follow the floor:

- The macOS 27 SDK ships with Xcode 27, released 2026-09-14, which needs macOS 26.6 or
  later to run; the Xcode pinned today, 26.5, carries the macOS 26.5 SDK.
- CI's macOS jobs run on GitHub's `macos-26` image: macOS 26.6.2, with Xcode up to 26.6
  and no Xcode 27. The launch and smoke tests launch the app on the runner, so they need
  a runner on macOS 27, and so do the package's tests once `platforms:` says 27.
- GitHub's `xcode-27` image runs macOS 27.0 with Xcode 27.0 as its default. It is the
  only hosted image on macOS 27 today, and it is in Preview: its runs fall outside the
  Actions SLA.

## Decision drivers

- The owner's decision that macOS 27 is the floor (kickoff, 2026-09-30).
- Every gate `just check` and CI run today keeps running; none is paused or loosened to
  fit the floor (`AGENTS.md` › Security and human approval).
- One toolchain everywhere: the Xcode the owner builds with is the one CI builds with
  (`.claude/rules/project.md` › Toolchain Pinning).

## Considered options

1. **macOS 27.0, with CI on the `xcode-27` Preview image** — every gate keeps running,
   on an image without an SLA.
2. **macOS 27.0, with CI kept on `macos-26`** — the package tests could stay on a lower
   floor, but the launch and smoke tests could not run until a GA macOS 27 image exists,
   which pauses two gates.
3. **macOS 26.4**, the lowest floor the APIs allow — CI unchanged, but support claimed
   for an OS and a model nobody runs.

## Decision

The floor is macOS 27.0 in both places that state it: `deploymentTarget.macOS: "27.0"`
in `project.yml` and `platforms: [.macOS("27.0")]` in `Package.swift` (the string form
works with the current `swift-tools-version: 6.2`). The project builds with Xcode 27, so
the SDK matches the floor: `.xcode-version` moves from 26.5 to 27.0, and every macOS job
in `.github/workflows/`
moves from `runs-on: macos-26` to `runs-on: xcode-27`. The CI convention of deriving
`DEVELOPER_DIR` as `/Applications/Xcode_<version>.app` holds there: the image links
`/Applications/Xcode_27.0.app` to its Xcode 27.0.

Option 1 beat option 2 because pausing the launch and smoke tests weakens two gates for
as long as GitHub's schedule takes; it beat option 3 because the owner set the floor, and
a 26.x floor would be support nobody exercises.

## Consequences

### Positive

- The app, its tests, and CI all run on the OS the app is used on.
- No `@available` check is needed for anything the app calls.

### Negative

- CI rests on a Preview image: no SLA, and it may change before GA. When GitHub ships a
  GA image on macOS 27, the `runs-on:` labels move to it.
- Everyone who builds the app needs Xcode 27, on macOS 26.6 or later.
- The launch and smoke tests run where Apple Intelligence is, as far as anyone has
  checked, unavailable, so they see the model-unavailable state (ux-flows S7), never a
  town.

### Follow-ups

- The owner installs Xcode 27 (a human step).
- One `ci:` pull request moves the pin and the images together: `.xcode-version` to
  27.0, every `runs-on: macos-26` to `xcode-27`, `docs/getting-started.md`'s Xcode
  requirement, and `deploymentTarget` and `platforms:` to 27.0 (`changing-gates`) — an
  issue in the backlog.

## Open questions

- Unverified: whether Apple Intelligence is ever available inside a macOS virtual
  machine such as a CI runner. Nothing here depends on it.

## Sources

- The macOS 26.5 SDK's `FoundationModels.swiftinterface` (Xcode 26.5, 17F42):
  `SystemLanguageModel`, `LanguageModelSession`, and the `Generable` macro are
  `@available(… macOS 26.0 …)`; `contextSize` is `@backDeployed(before: … macOS 26.4 …)`;
  `tokenCount(for:)` is `@available(… macOS 26.4 …)` — checked 2026-09-30
- <https://developer.apple.com/news/releases/> — Xcode 27 (27A266a) released 2026-09-14 —
  checked 2026-09-30
- <https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes> —
  "Xcode 27 requires a Mac running macOS Tahoe 26.6 or later."; it ships the macOS 27 SDK
  — checked 2026-09-30
- <https://github.com/actions/runner-images> — `macos-26` is GA; the Xcode 27 image,
  labels `xcode-27` and `xcode-27-xlarge`, is Preview; a beta image's workflows "do not
  fall under the customer SLA in place for Actions" — checked 2026-09-30
- <https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md>
  — macOS 26.6.2 (25G83); Xcode 26.6 (default) down to 26.0.1, no Xcode 27 — checked
  2026-09-30
- <https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md>
  — macOS 27.0 (26A428); Xcode 27.0 (default, 27A266a), 27.1, and 27.2 beta; Xcode 27.0
  at `/Applications/Xcode_27.app`, linked as `/Applications/Xcode_27.0.app` — checked
  2026-09-30
- Experiment on this repository's toolchain, 2026-09-30: a package with
  `swift-tools-version: 6.2` and `platforms: [.macOS("26.4")]` resolved and built with no
  error.

## Related

- [ADR-0005](0005-foundation-models-in-core.md) — the framework this floor is set for.
