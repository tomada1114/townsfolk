# What `scripts/guard/` blocks, and what it deliberately does not

The detail behind `changing-gates`' `scripts/guard/` section. `scripts/guard/paths.sh`
and `scripts/guard/credentials.sh` remain the authoritative list.

- **Blocked by path:** `.env`, `.env.*`, and `.envrc.*` (except
  `.example`/`.sample`/`.template`), `.claude/settings.local.json`,
  any `secrets` path segment, signing material and credential files (`.p12`,
  `.pfx`, `.p8`, provisioning profiles, keychains, `*key*.pem`, `.netrc`,
  `credentials.json`, `secrets.json`, `private-key.*`), and `Local.xcconfig` — the
  per-machine Debug signing identity `Config/Debug.xcconfig` optionally includes,
  which is gitignored as well.
- **Blocked by content:** literal patterns for a PEM private-key header, GitHub tokens,
  AWS access key ids, an AWS secret access key assigned to its variable name,
  Anthropic and OpenAI API keys, Slack tokens, Google API keys, Stripe live keys (not
  test keys), and JWTs. It prints the category, never the matched text.
- **Deliberately not blocked:** `.cer` and `.certSigningRequest` (public), `.key`
  (collides with Keynote documents), a regenerated `Package.resolved`, and anything
  that needs judgment rather than a pattern — no entropy heuristic. Whether a commit
  *should* contain what it contains stays in PR review.
