# ADR-0002: Keep the App Sandbox, and add no entitlement

- **Status:** Accepted 2026-09-30
- **Date:** 2026-09-30
- **Deciders:** the owner

## Context

`App/Townsfolk.entitlements` ships with `com.apple.security.app-sandbox` and nothing else,
and the template keeps the sandbox on unless an app needs something it forbids
(`docs/distribution.md` › Sandboxed or not). Townsfolk needs:

- the on-device model, through the Foundation Models framework (ADR-0005);
- its own database and preferences, inside its container (ADR-0004);
- to know whether its window is visible (ADR-0006);
- to send the person to System Settings when Apple Intelligence is off (ux-flows S7).

It needs no network (the non-goal "Network access"; requirements §4, "Local only"), no
other app's windows or input, no file the person did not create through it, and no
privacy permission.

## Decision drivers

- Requirements §4: no network access, and all data stays in the app's container.
- Keeping every distribution channel open, since ADR-0009 leaves the channel undecided.
- `AGENTS.md` › Security and human approval: an entitlement is a human's decision.

## Considered options

1. **Sandbox on, no entitlement added.**
2. **Sandbox on, plus `com.apple.security.network.client`** — nothing in this version
   uses the network.
3. **Sandbox off** — nothing in this version needs it.

## Decision

The entitlements file stays as the template ships it: the App Sandbox on and no other
entitlement. `project.yml` declares no `INFOPLIST_KEY_NS…UsageDescription` key, and the
app asks for no TCC permission.

Without `com.apple.security.network.client` the sandbox gives the app no outgoing
network connection, so "nothing leaves the Mac" is enforced by the OS rather than only
promised by the code. The Foundation Models documentation names no entitlement for the
on-device model; the one entitlement it mentions is for Private Cloud Compute, which
Townsfolk does not use.

## Consequences

### Positive

- The privacy promise in requirements §4 holds even against a bug that reaches for the
  network.
- The Mac App Store stays possible: its guidelines require a sandboxed Mac app.
- No permission prompt, no onboarding for one, and no way for the app to half-work
  because a permission was refused.

### Negative

- Outside information and external integrations (both Later) need the network client
  entitlement, and screenshot input (Next) would need Screen Recording if it captured
  the screen instead of taking an image the person hands it. Each is a new ADR, and the
  first two also change the non-goal "Network access".

### Follow-ups

None: the file is already in this state.

## Open questions

None.

## Sources

- <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client>
  — "A Boolean value indicating whether your app may open outgoing network
  connections."; macOS 10.7+ — checked 2026-09-30
- <https://developer.apple.com/documentation/foundationmodels> — no entitlement or
  Info.plist key for the on-device model; `com.apple.developer.private-cloud-compute` is
  the only entitlement mentioned — checked 2026-09-30
- <https://developer.apple.com/app-store/review/guidelines/> — guideline 2.4.5(i): Mac
  apps "must be appropriately sandboxed, and follow macOS File System Documentation." —
  checked 2026-09-30

## Related

- [ADR-0004](0004-persistence-sqlite-in-core.md) — the store lives in the container this
  keeps.
- [ADR-0009](0009-not-distributed-yet.md) — the channels this keeps open.
