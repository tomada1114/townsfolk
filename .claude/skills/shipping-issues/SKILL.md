---
name: shipping-issues
description: >-
  Rank open GitHub Issues by their `priority: P0`-`P3` labels -- backfilling a missing
  label from how much an issue unblocks and how far its impact spreads -- then implement
  the top one, open a PR that auto-closes the issue (Closes #N), wait for the automatic
  Codex review GitHub posts on that PR and address its accepted findings once, watch CI
  to green on the current head, merge with no approval pause, and return the checkout to
  the default branch. With no argument it ships the highest-priority issue and then what
  that run itself produced. Pass "all" to work through every issue in dependency order,
  independent ones implemented in parallel git worktrees, with review, CI and merge
  still serialized. Use when asked to ship the remaining issues, take on the next issue,
  or clear the ticket backlog.
---

# Shipping Issues

**Owns:** taking open issues to a merged PR and a CLOSED issue. **Does not own:** the
label vocabulary and issue-body rules (`triaging-issues`); test-first Core work (`tdd`).

**Done means all three:** the PR is merged, the issue is CLOSED, and nothing was deleted
or weakened to get there. **Invoking this skill authorizes every write it makes, merge
included** -- the standing exception in `AGENTS.md`'s "Security and human approval", and
nothing else that section lists. The go-ahead to merge is a completed Codex review
with its accepted findings addressed plus `PASS` on the current head: merge in that same
turn. The only pauses: the [stop conditions](#stop-conditions), a tied top two (step 2),
`NO_CHECKS` with no local gate (step 6).

## Modes

| Argument | Behavior |
|---|---|
| _(none)_ | Ship the top shippable issue, then only **its own output** (step 8c). |
| `all` | Every shippable issue, dependency-then-priority order; independent ones implemented in parallel worktrees, review/CI/merge serialized. |
| a number | That issue, once nothing it depends on is open. |

A count sets `--max-parallel` (default 3, raised only when asked). A `blocked: design`
or `design=open` issue ships only when named or with `--include-design` (step 2b).

## Working rules

- **One checkout, one writer**, fixed at step 1 for the batch: **serial** works in the
  main checkout; **parallel** gives each issue `<runstate>/worktrees/<n>` and leaves the
  main checkout clean. Never re-decide mid-batch.
- **Concurrency stops at the GitHub API:** step 3 runs concurrently; every GitHub call
  stays in this session, and steps 5-7 take one PR at a time.
- **Nothing waits on the user mid-run.** Never `rm`; use `mv` into
  `<runstate>/holding/<n>/`, `git rm`, or `git checkout --`, and defer anything else
  approval-gated to the end ([closing-out.md](references/closing-out.md#approval-gated-commands)).
- Every issue starts from, and every merge returns to, an up-to-date default branch.
  **After a context compaction, re-read `<runstate>/run.md`** before the next write
  ([recovery.md](references/recovery.md#after-a-context-compaction)).

## Sub-agents and run state

Spawn by `subagent_type`, naming a `.claude/agents/` tier, never a bare `model`:
`executor` for a settled spec (implementation, review fix, CI repair); `architect` for
foundational implementation, priority research, a CI failure that survived two
attempts, and design decisions; `worker` for tool-free drafting from a complete brief
([cost-discipline.md](references/cost-discipline.md#model-tiers)) with a
`references/agent-*.md` brief. **Reuse before respawn:** a resume or next repair attempt
goes to the same agent via `SendMessage`. Codex CLI has no tiers: run it inline.

Everything generated lives under `<runstate>` =
`${AGENT_SKILL_STATE_DIR:-$HOME/.local/state/agent-skills}/shipping-issues/<owner>__<repo>/`,
never in a checkout. Record events as they happen with `scripts/run_record.py`
([run-record.md](references/run-record.md)). **Requires:** `git`, `python3`, `gh`.

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

One issue, one branch, one PR; the plan's `next:` line is the command. Take a baseline
of the confirmed verify command (serial: once on the branch; parallel: through
`worktree_setup.sh`, the first worktree alone). Spawn
[agent-implementation.md](references/agent-implementation.md) per issue, a batch's
spawns in one message. Judge each result here: a `not-met` `ACCEPTANCE` line, an
unaccepted `UNRESOLVED` call, or a user-facing change without a `CHANGELOG.md` entry
under `[Unreleased]` goes back. At most 2 resumes; a third miss is `NEEDS-CLARIFICATION`
([implement-and-review.md](references/implement-and-review.md#3-implement)). **No local
review runs** -- no `/code-review`, no review agent: step 5's Codex review is the review.

## 4. Open the PR

Right after step 3 accepts a branch (parallel: each branch, in batch order) -- opening
starts the review and CI. Push; no commits -> `SKIPPED(<why>)`. Open a **regular,
non-draft** PR against the default branch: `PR-TITLE`, then `PR-SUMMARY`, **`Closes
#N`**, `TEST-PLAN`. Record `--event pr-created`, run `link_check.sh <pr> --issue <n>
--fix` ([pr-ci-merge.md](references/pr-ci-merge.md#4-open-the-pr)).

## 5. The Codex review

The GitHub integration has Codex (`chatgpt-codex-connector[bot]`) review every PR once,
shortly after it opens. That one review is this run's review:

```bash
${CLAUDE_SKILL_DIR}/scripts/codex_review.py <pr> --timeout <s> > <runstate>/review/<pr>.log
```

Wait as step 6 does (background `--timeout 600`, or foreground slices of
`--timeout 540`), **600 s in total**. `CLEAN`/`FINDINGS` -> triage every `F<n>`, fix
the accepted ones **once** (parallel: [agent-review-fix.md](references/agent-review-fix.md)),
read the fix diff, re-verify, push, record `--event review`. Never post `@codex review`,
never wait for a second review, never stand a local review in for a missing one.
`TIMEOUT` past 600 s or `FAILED` -> hold the PR unmerged, record `--event blocked`, move
on ([implement-and-review.md](references/implement-and-review.md#5-the-codex-review)).

## 6. CI to green

Once the current head shows among the PR's runs, watch it into `<runstate>/ci/<pr>.log`.
The Bash tool kills a foreground call at 600 s: run `ci_watch.sh <pr> --timeout 1800`
with `run_in_background` and wait for its notification -- never a hand-rolled sleep/poll
loop -- or in the foreground with `--timeout 540`, re-run on `TIMEOUT`
([pr-ci-merge.md](references/pr-ci-merge.md#6-ci-to-green)). `FAIL` ->
[agent-ci-repair.md](references/agent-ci-repair.md), 3 attempts at most. Anything else ->
[recovery.md](references/recovery.md#no_checks-error-and-other-non-verdicts). `PASS` ->
step 7 in the same turn.

## 7. Merge and confirm the issue closed

Run `land_pr.sh <pr> --issue <n> --head-sha <sha>`, `<sha>` the log's `head_sha:`, and
read `result:` and `issue:` ([landing-outcomes.md](references/landing-outcomes.md)). A
PR waiting on a required human review is **held and reported, never armed for
auto-merge**. Record `--event merged`, then `git switch <default_branch> && git pull
--ff-only`. **Clear what the merge unblocked**, as `triaging-issues` asks of whoever
lands a blocker: re-plan with `--refresh` and run its `stale-labels:` command. Then
continue ([pr-ci-merge.md](references/pr-ci-merge.md#7-merge-and-confirm-the-issue-closed)).

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
signing, a new dependency, `just labels`, `just ruleset`).

Also stop on **a change this run did not make** -- a dirty main checkout no step
touched, a branch moved underneath you, the default branch ahead of the last merge, a
worktree under this run's root it did not create. Prove it is not yours, leave it exactly
as found, record `--event blocked`, and ask
([recovery.md](references/recovery.md#a-change-this-run-did-not-make)).

In `all` mode one failed or held issue does not stop the run: mark it FAILED or HELD,
skip its dependents, continue. A background `DEFERRED` design never stops a run (step 2b).
