# ADR-0009: Not distributed in this version

- **Status:** Accepted 2026-09-30
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

The template builds for distribution outside the Mac App Store: pushing a `v*` tag runs
`.github/workflows/release.yml`, which signs with Developer ID and notarizes when the
secrets exist and otherwise produces an ad-hoc-signed DMG (`docs/distribution.md`).
Townsfolk is for its developer first, built so that others could use it too (`AGENTS.md`
› Product). The requirements left two questions to the owner (§6): the Mac App Store or
a signed and notarized DMG; and, if the app is shared, how it stands against the
Foundation Models acceptable-use requirements, which prohibit a use that "Enables
dependency or spiraling user interactions detrimental to a user's mental health". The
non-goals keep the app away from engagement hooks, and the owner wants to judge the
question from their own use first.

## Decision drivers

- The owner's judgment of the acceptable-use requirement, formed by using the app.
- No cost and no secret before one is needed.
- Every channel kept open.

## Considered options

1. **A signed and notarized DMG** through the template's release workflow — an Apple
   Developer Program membership and the signing secrets.
2. **The Mac App Store** — App Review, App Store Connect, and the name "Townsfolk" free
   there; the sandbox it requires is already on (ADR-0002).
3. **Both.**
4. **Not yet.**

## Decision

This version is not distributed. The owner runs a build of this repository (`just run`);
no `v*` tag is pushed, so the release workflow never runs; no signing or notarization
secret is configured; and the app icon stays a placeholder (ADR-0008). Nothing is
removed: the release workflow and `docs/distribution.md` stay as the template ships them.

When the owner wants to release, they file an issue for it. Its ADR chooses the channel,
records the acceptable-use stance, and supersedes this one.

## Consequences

### Positive

- No membership fee and no secrets now, and no release chores while the MVP settles.
- Every channel stays open: the sandbox stays on (ADR-0002) and the release workflow is
  unchanged.

### Negative

- Nobody but a developer who builds from source can run the app, so "built so that
  others could use it too" waits, and whether anyone but the owner finds it fun
  (requirements §6) stays unknown.

### Follow-ups

None now. The release issue is the owner's to file.

## Open questions

- Owner decides, at release: the Mac App Store, a signed and notarized DMG, or both.
- Owner decides, from their own use: how the app stands against the acceptable-use
  requirement quoted above.

## Sources

- <https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/>
  — among the prohibited uses, "Enables dependency or spiraling user interactions
  detrimental to a user's mental health"; the page shows no date — checked 2026-09-30
- <https://developer.apple.com/support/enrollment/> — "The Apple Developer Program annual
  fee is 99 USD" — checked 2026-09-30
- <https://developer.apple.com/app-store/review/guidelines/> — guideline 2.4.5(i): Mac
  apps "must be appropriately sandboxed" — checked 2026-09-30

## Related

- [ADR-0002](0002-sandbox-posture.md) — keeps the Mac App Store possible.
- [ADR-0008](0008-design-lock.md) — the icon that waits for a release.
