# PR, CI, and merge

The detail behind SKILL.md steps 4, 6 and 7 (step 5, the Codex review, is
[implement-and-review.md](implement-and-review.md#5-the-codex-review)). A PR opens as
soon as step 3 accepts its branch -- in parallel mode every branch of the batch, in the
batch's dependency-then-priority order -- so each Codex review starts at once. From step
5 to step 7 the run is serial in both modes: one PR at a time, in that same order.
Finish an issue's review -> CI -> merge before taking up the next.

## Table of Contents

- [4. Open the PR](#4-open-the-pr)
- [6. CI to green](#6-ci-to-green)
  - [Waiting inside the 600-second cap](#waiting-inside-the-600-second-cap)
  - [Reading the verdict](#reading-the-verdict)
- [7. Merge and confirm the issue closed](#7-merge-and-confirm-the-issue-closed)
  - [Clearing `blocked: dependency`](#clearing-blocked-dependency)
  - [Moving on](#moving-on)

## 4. Open the PR

Commits but nothing pushed -> push from this session (`git -C <workdir> push -u origin
<branch>`). No commits at all -> no branch: record `--event blocked --field issue=<n>`,
report `SKIPPED(<why>)`, and in `all` mode move on.

Open a **regular** PR -- never a draft: marking a draft ready is a second review
trigger, and `land_pr.sh` marks one ready before merging -- from `<branch>` against
`<default_branch>`, titled `<PR-TITLE>`. The body must carry **`Closes #N`** after the
summary (a bare `#N` closes nothing) and target the **default branch** (auto-close
only fires there). Build it from `PR-SUMMARY`,
`Closes #N`, and `TEST-PLAN`, in the shape of `.github/pull_request_template.md` --
Summary, Test Plan, and its Checklist ticked only for what actually ran. Record
`--event pr-created --field issue=<n> --field pr=<url>`, then:

```bash
${CLAUDE_SKILL_DIR}/scripts/link_check.sh <pr> --issue <n> --fix
```

Run it before step 5's wait and step 6's watch start: every body edit it makes fires the
PR's `edited` event, which re-runs the PR-title and labeling workflows, and a run
cancelled by the next edit must not land inside a watch. `land_pr.sh` re-checks the link
at step 7 without `--fix`; this earlier call is not redundant, because it is the only one
that repairs, and it catches `WRONG_BASE` before CI spends its time on the wrong base.
`WRONG_BASE` -> retarget before merging. When GitHub lists no link to the issue, `--fix`
reads the body first and never adds a second keyword:

- **No closing keyword for `#N` in the body** -> it appends `Closes #N`.
- **The keyword is there, or was just appended, and GitHub still lists no link** -> it
  re-saves the body: a minimal body of only `Closes #N`, then the full body put back, at
  most 2 times (4 edits), a few seconds apart, stopping as soon as the link appears. The
  full body is restored after every minimal save, including on an interrupt; if it
  cannot be, the verdict is `ERROR` and the detail names the file holding the full body
  and the `gh pr edit` that puts it back (the PR description's edit history on GitHub
  keeps it too) -- restore it before anything else. A body it could not read is never
  rewritten (`ERROR`).

`NOT_LINKED`'s `detail:` says which case is left. "has no Closes/Fixes/Resolves
keyword", or "closes #M but not the target issue #N", means the body still lacks the
keyword: re-run `--fix`, or add `Closes #N` by hand. "has a closing keyword for #N, but
GitHub has not linked it" means the re-saves left the link missing: go on anyway. Step
7's `land_pr.sh` then refuses the merge with `result: NOT_LINKED`, and the PR is held for
the human ([landing-outcomes.md](landing-outcomes.md)): merging it with
`--no-link-check` is their decision, never this run's.

## 6. CI to green

Watch only once step 5 is done -- the review read, and its fix pushed if it had one --
so the watch is about the head that will merge. Wait for that head commit to appear
among the branch's CI runs before watching -- the checks API serves the previous
commit's results for a minute or two after a push, and a stale PASS is worse than a
stale FAIL
([recovery.md](recovery.md#ci-reports-the-previous-commit)). Then watch the PR once,
output redirected -- raw output carries failing-run log tails that must stay out of this
context -- and read only these lines:

```bash
${CLAUDE_SKILL_DIR}/scripts/ci_watch.sh <pr> --timeout 1800 > <runstate>/ci/<pr>.log
grep -E '^(verdict|waited_seconds|head_sha|mergeable|merge_state|review_decision):' <runstate>/ci/<pr>.log
```

One watch per PR; keep the log's `failed_checks:` for repair, and its `head_sha:` for
step 7. Record `--event ci`.

### Waiting inside the 600-second cap

The Bash tool kills a foreground call after at most 600 seconds, while this repository's
CI (lint, tests with coverage, build, UI test, Release smoke) routinely runs longer. A
`--timeout 1800` watch in the foreground would be killed mid-wait, with no verdict and a
truncated log. So pick one of these, in this order:

1. **Background, then wait for the notification (Claude Code).** Start the command
   above with the Bash tool's `run_in_background`. The host re-invokes this session when
   the command exits; read the lines then. This is the run's only wait primitive --
   never a hand-rolled `sleep`/poll loop, which burns turns and context. Until that
   verdict is read, nothing else on the shipping path moves -- no next step 3, no other
   PR's review, watch, or merge, no checkout or branch switch; the only work allowed
   meanwhile is draining step 8b's queue or drafting a follow-up body.
2. **Foreground, under the cap.** Run it with `--timeout 540` or less. `verdict:
   TIMEOUT` then means only that the watch's own bound ran out, not that CI failed: run
   the same watch again, until 1800 seconds of watching have passed in total.

After 1800 seconds of `TIMEOUT` in total, treat it like `ERROR`: re-read the PR's
actual CI state before deciding anything.

### Reading the verdict

- `PASS` -> step 7 **in the same turn**. Do not report the green CI and wait: green CI
  is the approval.
- `FAIL` -> [recovery.md](recovery.md#ci-fails) and
  [agent-ci-repair.md](agent-ci-repair.md), at most 3 attempts. The second and third
  attempts go to the same repair agent by `SendMessage` while it is reachable, with what
  the previous attempt tried; once the same failure has survived two attempts, a fresh
  `architect` takes the third.
- `TIMEOUT` -> not a verdict on the code: wait again, up to 1800 s in total; past that,
  treat it as `ERROR`.
- `NO_CHECKS`, `ERROR` ->
  [recovery.md](recovery.md#no_checks-error-and-other-non-verdicts).

## 7. Merge and confirm the issue closed

```bash
${CLAUDE_SKILL_DIR}/scripts/land_pr.sh <pr> --issue <n> --head-sha <head_sha>
```

`<head_sha>` is the `head_sha:` line of the `PASS` in `<runstate>/ci/<pr>.log` -- the
commit CI verified. The merge is pinned to it (`gh pr merge --match-head-commit`), so a
push that landed after the watch makes GitHub refuse the merge instead of merging an
unverified commit (`MERGE_REFUSED`: watch CI again). When the log has no `head_sha:`
line, omit the flag: the script then pins to the head it reads just before it checks the
merge state.

Merge as soon as step 6 reports `verdict: PASS` on a PR whose step 5 is done -- call
`land_pr.sh` in that same turn. Do not ask whether to merge, and do not report the green
CI and wait. The script merges only a `CLEAN` merge state and never arms auto-merge: a
PR that waits on a required human review is held and reported. Read `result:` and
`issue:` -- every result, and the two that must never read as success:
[landing-outcomes.md](landing-outcomes.md). Record `--event merged`. Then:

```bash
git switch <default_branch> && git pull --ff-only
```

after every merge, and again as the run's last act -- a run never ends parked on a
feature branch. In parallel mode the main checkout is already there; pull anyway so it
carries the merge that just landed.

### Clearing `blocked: dependency`

`triaging-issues` defines the rule: the label is not removed automatically when a
blocker closes, and whoever lands the blocking issue clears it from every issue that
named it. This run just landed one, so this run clears them, right after the merge:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/plan.py --mode <same> --refresh --allow-existing-worktrees
```

Its `stale-labels:` line names every open issue still labeled `blocked: dependency`
whose `Depends on` blockers are now all closed, with the exact
`apply_priority_labels.py --clear-dependency` command to run. Run it without asking. Two
cases it leaves alone on purpose: an issue with another blocker still open (the label is
still true), and a label with no `Depends on` line to verify it against (the label rule
in `triaging-issues` requires one; report it at step 10 rather than guess). Do not pass a
`--label` filter to this re-plan: a dependent outside the filter would be missed.

### Moving on

**Serial `all`:** the same re-plan's `select:` line is the next issue; start its step 3
from this up-to-date branch, without pausing. **Parallel `all`:** the batch's remaining
branches are now behind; bring each up to date in its own worktree **before its own
step 6 watch** (in the same push as its review fix, when it has one), rather than after
a CI failure, and merge rather than rebase
([how](recovery.md#bringing-the-rest-of-a-parallel-batch-up-to-date)). A conflict
either way means the grouping call was wrong for that pair
([recovery.md](recovery.md#a-merge-conflict)). Only when the whole batch has merged
does the run group the next batch. With no argument or an explicit number, step 8c is
the only thing that extends the run past this merge.
