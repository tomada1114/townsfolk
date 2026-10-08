---
name: shipping-issues
description: >-
  Claude Code only, outside a cloud session. Rank open GitHub Issues by their
  `priority: P0`-`P3` labels, backfilling missing ones, then implement the top issue, open a PR that closes it, wait for the PR's automatic Codex
  reviews (up to 3) and fix their accepted findings, watch CI to green, merge, and return to the
  default branch. Pass "all" to work through every issue in dependency order, independent
  ones in parallel git worktrees. Use when asked to ship the remaining issues, take on the
  next issue, or clear the ticket backlog.
---

# Shipping Issues (Claude Code)

Claude Code only. In Codex, use `codex-shipping-issues`; do not run this workflow. A
Claude Code cloud session (`CLAUDE_CODE_REMOTE=true`) is unsupported here -- it has no
Xcode -- and preflight stops there. **Done:** review settled, PR merged, issue CLOSED, no gate
deleted or weakened.

**Invoking this skill is the sign-off for exactly the remote writes it lists, for this
invocation, up to and including the merge** -- the standing exception in `AGENTS.md`'s
"Security and human approval": priority and status labels, pushing its own branches,
creating the PR, merging it, filing and labelling follow-up issues, step 8b's design
comments, and deleting its own branches at cleanup. Anything outside that list stops and
asks: a force-push, a hook bypass, a weakened gate, a new dependency (proposed, then the
run waits for sign-off), `just labels` (a missing label definition stops the label
scripts with exit 4), an `@codex review` comment, or a reply to or resolution of a
review thread. The go-ahead is a settled [step 5](#5-wait-for-the-pr-review) plus
[step 6](#6-ci-to-green)'s `PASS` for the current head: the merge happens in that same
turn, with no "shall I merge?" and no summary-then-wait. Re-confirming per issue defeats
`all` mode entirely. The only pauses are the [Stop conditions](#stop-conditions) and two
narrow asks named inline: a genuinely tied top two at step 2, and `NO_CHECKS` at step 6.

## Modes

| Argument | Behavior |
|---|---|
| _(none)_ | Ship the top shippable issue, then only **its own output** (step 8c). |
| `all` | Every shippable issue, dependency-then-priority order; independent ones implemented in parallel worktrees, review/CI/merge serialized. |
| a number | That issue, once nothing it depends on is open. |

A count sets `--max-parallel` (default 3, raised only when asked). A `blocked: design`
or `design=open` issue ships only when named or with `--include-design` (step 2b).

## Working rules

- **One checkout, one writer.** Step 1 decides once per batch -- never re-decide it
  mid-batch: **serial** works in the main checkout, one issue start to finish;
  **parallel** gives each issue a worktree under `<runstate>/worktrees/<n>` and leaves
  the main checkout clean. All GitHub traffic stays in this session, one PR at a time.
- **Nothing waits on the user mid-run.** A command your host's permission settings gate
  behind an approval prompt (typically `rm -rf`) stalls the run: take a prompt-free
  equivalent (`mv` into the holding area, not `rm`), else defer it to the one end-of-run
  confirmation, else run it mid-run only when the issue cannot move without it
  ([closing-out.md](references/closing-out.md#approval-gated-commands)).
- **Inline by default; tiers by name.** On a host with named sub-agents (AGENTS.md
  "Sub-agents"), a brief (`references/agent-*.md`) may go to the `worker`, `executor`,
  or `architect` tier [cost-discipline.md](references/cost-discipline.md#tier-assignment)
  names -- by tier name, never a bare model name. A patch round or repeat CI repair on
  the same tier continues the same agent where the host allows.
- **State lives in `<runstate>`** ([run-record.md](references/run-record.md)), never
  inside a checkout -- an untracked path there is a hard stop. Record each event as it
  happens with `scripts/run_record.py`; **re-read `<runstate>/run.md` after a context
  compaction** or whenever unsure what this run already did
  ([recovery.md](references/recovery.md#after-a-context-compaction)).

## Run state

Everything generated lives under `<runstate>` =
`${AGENT_SKILL_STATE_DIR:-$HOME/.local/state/agent-skills}/shipping-issues/<owner>__<repo>/`,
never in a checkout. Scripts (`${CLAUDE_SKILL_DIR}/scripts/<name>`) run from the main
checkout's root. **Requires:** `git`, `python3`, `gh`. **Resumes go via `SendMessage`**
to the same agent where the host allows.

## 1. Plan

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/plan.py --mode <all|single|N> [--max-parallel N] \
    [--label L] [--assignee A] [--milestone M] [--include-design] --record
```

Read the block; do not re-derive it ([plan-output.md](references/plan-output.md)).

- `preflight: BLOCKED` stops the run; `tree: DIRTY` is a question to ask now;
  `existing-worktrees: BLOCKED` is a stop condition.
- `verify-check:` is a guess; confirm it. Here it is `just check` (`just test` skips
  lint, the harness checks, and the build).
- `needs-design:` -> spawn step 8b now. `stale-labels:` -> run its command unasked.
  `labels: COMPLETE` -> skip step 2. `github: write=no` -> report instead of writing.

## 2. Label the unlabeled

Three or fewer: read them against [priority-rubric.md](references/priority-rubric.md)
and run `apply_priority_labels.py --backfill --set N=P0 --quiet`. More, or a close top
two: one `architect` with [agent-priority-research.md](references/agent-priority-research.md).
Re-plan (`--refresh --record`) and proceed without asking. Exit 4 (label not defined)
needs `just labels`, outside this skill's sign-off: stop and ask.

## 2b. Decide a design that gates the pick

Only for a design-blocked pick taken on deliberately: decide, record, and clear it
before step 3 ([dependency-triage.md](references/dependency-triage.md#deciding-a-held-design)).

## 2c. Confirm the proposed batch

The plan proposes; this step decides. Look for what a script cannot see -- two issues
both editing `project.yml`, `Package.swift` or a workflow (a `CHANGELOG.md` entry is not)
([dependency-triage.md](references/dependency-triage.md#parallel-vs-sequential-all-mode)).
Take the narrower grouping on disagreement; shrinking never needs asking.

## 3. Implement

**Read [implement-and-review.md](references/implement-and-review.md) first.** Cut the
branch and take a baseline (parallel: `worktree_setup.sh`, the first worktree alone).
Run [agent-implementation.md](references/agent-implementation.md) per issue --
`executor`, `architect` when foundational, `worker` when small and settled -- and **judge
each result here**, `ACCEPTANCE` first. At most 2 patch rounds on the same tier (a
`worker` miss moves to `executor`); a third miss is `NEEDS-CLARIFICATION`.

## 4. Open the PR

Right after step 3 accepts a branch (parallel: each branch, in batch order) -- opening
starts the review and CI. Push; no commits -> `SKIPPED(<why>)`. Open a **regular,
non-draft** PR against the default branch: `PR-TITLE`, then `PR-SUMMARY`, **`Closes
#N`**, `TEST-PLAN`. Record `--event pr-created`, run `link_check.sh <pr> --issue <n>
--fix` ([pr-ci-merge.md](references/pr-ci-merge.md#opening-the-pr)).

## 5. Wait for the PR review

Each Codex review, on opening and maybe after a fix push, is a round, at most 3 per PR;
never ask for one. `${CLAUDE_SKILL_DIR}/scripts/review_watch.py <pr>` into `<runstate>/review/<pr>.log` alongside step
6 ([how](references/pr-ci-merge.md#waiting-for-the-pr-review)). `FINDINGS`: triage the
round's `F<n>`, fix the accepted (round 1 all, 2-3 `P0`-`P2`), verify, push, then CI and
`--after-push <sha>`. `NO_REVIEW`/`ERROR`/past 1800 s -> held for step 10, no local review.

## 6. CI to green

Once the current head shows among the PR's runs, watch it into `<runstate>/ci/<pr>.log`.
The Bash tool kills a foreground call at 600 s: run `ci_watch.sh <pr> --timeout 1800`
with `run_in_background` and wait for its notification -- never a hand-rolled sleep/poll
loop -- or in the foreground with `--timeout 540`, re-run on `TIMEOUT`
([pr-ci-merge.md](references/pr-ci-merge.md#waiting-inside-the-command-timeout)). `FAIL` ->
[agent-ci-repair.md](references/agent-ci-repair.md), 3 attempts at most. Anything else ->
[recovery.md](references/recovery.md#no_checks-error-and-other-non-verdicts). `PASS` ->
step 7 in the same turn.

## 7. Merge and confirm the issue closed

On `PASS` for the current head, step 5 settled, run **in that same turn**
`land_pr.sh <pr> --issue <n> --head-sha <sha> --review-log <runstate>/review/<pr>.log`,
`<sha>` the CI log's `head_sha:`, and read `result:` and `issue:` ([landing-outcomes.md](references/landing-outcomes.md)). A
PR waiting on a required human review is **held and reported, never armed for
auto-merge**. Record `--event merged`, then `git switch <default_branch> && git pull
--ff-only`. **Clear what the merge unblocked**, as `triaging-issues` asks of whoever
lands a blocker: re-plan with `--refresh` and run its `stale-labels:` command. Then
continue ([pr-ci-merge.md](references/pr-ci-merge.md#after-the-merge)).

## 8. Close out the findings the run turned up

Each defect outside the issue: fix it in the open diff, or file it and ship it now
(step 8c), or file it and leave it. Read [filing-followups.md](references/filing-followups.md),
then file with `file_followup.py` right after the PR that surfaced it lands.

## 8b. Unblock held designs in the background

Each `--needs-design` filing and `needs-design:` issue gets one `architect` with
[agent-design-decision.md](references/agent-design-decision.md). **Spawn and move on;**
at most 3 in flight, drained on each completion notification. `DEFERRED` is a correct
outcome, not a stop ([dependency-triage.md](references/dependency-triage.md#the-background-round)).

## 8c. Take the run's own output back into the queue

Before cleanup, ship step 8's follow-ups and step 8b's unblocked issues through steps
3-8 when all hold: **depth 1**, the
[readiness gate](references/dependency-triage.md#readiness-gate), and
[budget left](references/cost-discipline.md#run-budget). Otherwise name it at step 10
([filing-followups.md](references/filing-followups.md#shipping-what-the-run-filed-step-8c)).

## 9. Clean up

Once, after the last merge: one `cleanup_run.sh` call naming every branch this run
created as `--branch <name>` (without it, every merged-PR branch in the repository
goes). Then persist a probed worktree verdict and offer the holding area in one final
approval-gated call ([closing-out.md](references/closing-out.md#cleanup-scope)).

## 10. Report

No fixed format, but a fixed list of facts
([closing-out.md](references/closing-out.md#what-the-report-must-not-omit)): above all,
any issue open behind a merged PR, any PR held unmerged and why, any `not-met`
criterion, every `DEFERRED` question.

## Stop conditions

Stop the whole run and report when: the plan is `BLOCKED`, a dependency cycle needs a
human, a merge conflict needs a product decision, the repository requires linear
history (`--event blocked --field reason=linear-history`), the same CI failure survives
the retry ceiling on two issues, or the fix needs a write `AGENTS.md`'s "Security and
human approval" keeps outside this skill's exception (a gate change, entitlements or
signing, a new dependency, `just labels`, `just ruleset`), or two PRs end `NO_REVIEW`.

Also stop on **a change this run did not make** -- a dirty main checkout no step
touched, a branch moved underneath you, the default branch ahead of the last merge, a
worktree under this run's root it did not create. Prove it is not yours, leave it exactly
as found, record `--event blocked`, and ask
([recovery.md](references/recovery.md#a-change-this-run-did-not-make)).

In `all` mode one failed or held issue does not stop the run: mark it FAILED or HELD,
skip its dependents, continue. A background `DEFERRED` design never stops a run (step 2b).
