# Private repository setup

The template's workflows assume a public repository. On a private repository created
from it, three of them fail or mean nothing, and one of the required checks in
`.github/rulesets/main.json` can then never pass, so no pull request can merge. The
fix is documentation, not `if:` guards: a skipped job never reports its check, so a
guarded job would still leave a required context unsatisfied forever.

Do these steps after the bootstrap commit and before `just ruleset`.

## 1. Delete the workflows a private repository cannot run

| File | Why it goes |
|---|---|
| `.github/workflows/scorecard.yml` | OpenSSF Scorecard analyses public repositories only, and its upload to code scanning needs GitHub Advanced Security on a private one |
| `.github/workflows/codeql.yml` | CodeQL code scanning on a private repository needs GitHub Advanced Security (GitHub Code Security) |
| `.github/workflows/dependency-review.yml` | `actions/dependency-review-action` on a private repository needs GitHub Advanced Security |

Keep any of them if the plan includes GitHub Advanced Security for this repository.
`osv-scan.yml` runs without it and stays as the dependency-vulnerability check.

## 2. Remove the attestation step from `release.yml`

Delete the `Attest build provenance` step (`actions/attest-build-provenance`) in
`.github/workflows/release.yml`, and the `attestations: write` permission of the same
job, unless the plan supports artifact attestations on private repositories (GitHub
Enterprise Cloud). The `Create GitHub Release` step still works: the release and its
DMG are visible only to people with access to the repository.

## 3. Drop the matching required contexts before `just ruleset`

In `.github/rulesets/main.json`, remove this entry from `required_status_checks`
when `dependency-review.yml` was deleted:

```json
{ "context": "Dependency Review", "integration_id": 15368 }
```

Neither Scorecard nor CodeQL is a required context, so deleting them needs no ruleset
edit. Keep the remaining contexts — `Lint & Format Check`, `Test & Coverage Gate`,
`App Build, UI Test & Smoke`, `Workflow Security Lint`, and `Validate PR title`
(`scripts/bootstrap.sh` already removed `Template Bootstrap Smoke`). Then run
`scripts/tests/apply-ruleset_test.sh`, and `just ruleset` as a repository admin
(branch rulesets on a private repository need a paid GitHub plan).

## 4. Verify

Run `just lint` and `just check-harness` (actionlint and the workflow pin check read
the remaining workflows), commit, and open a pull request: every required check it
waits for is now one a job in the repository reports.
