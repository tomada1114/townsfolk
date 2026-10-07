# Implementing a branch and addressing its Codex review

The detail behind SKILL.md steps 3 and 5: what runs, in which checkout, what this session
does with each thing a sub-agent returns, and how the PR's one Codex review is waited
for, read, and answered. Read it at step 3 the first time in a run, and at step 5 the
first time a review comes back.

## Table of Contents

- [3. Implement](#3-implement)
  - [Serial](#serial)
  - [Parallel](#parallel)
  - [Spawning](#spawning)
  - [Judging what came back](#judging-what-came-back)
  - [Resuming a run](#resuming-a-run)
- [5. The Codex review](#5-the-codex-review)
  - [The single-review policy](#the-single-review-policy)
  - [Waiting for it](#waiting-for-it)
  - [Reading the verdict](#reading-the-verdict)
  - [Triage](#triage)
  - [Fixing the accepted findings once](#fixing-the-accepted-findings-once)
  - [Recording it](#recording-it)

## 3. Implement

One issue = one branch = one PR. Step 1's `next:` line is the command.

### Serial

```bash
git switch <default_branch> && git pull --ff-only && git switch -c <branch>
```

Then run the confirmed verification command (`just check` in this repository) **once,
unmodified, on this branch**, redirected to `<runstate>/verify/<n>-baseline.log`. Read
the exit code and the log's tail, never the full output.

### Parallel

The script creates each branch, copies untracked local config (`Config/Local.xcconfig`,
`.claude/settings.local.json`, and the other patterns in
[worktree-parallelism.md](worktree-parallelism.md#what-a-fresh-worktree-is-missing)),
installs dependencies when a lockfile asks for them, and runs the baseline, bounded. It
**reports and does not decide**:

```bash
git switch <default_branch> && git pull --ff-only   # once, before the batch
${CLAUDE_SKILL_DIR}/scripts/worktree_setup.sh --spec <n>:<branch> \
    --spec <m>:<branch> --base <default_branch> --root <runstate>/worktrees \
    --log-dir <runstate>/verify --verify "just check"
```

**Provision the first worktree on its own, read its block, then ask for the rest.** That
one extra call is what stops a repository that cannot carry a worktree from costing
three setups instead of one. Judging the four `baseline:` outcomes is yours, not the
script's ([recovery.md](recovery.md#a-red-baseline); `verdict:` semantics in
[worktree-parallelism.md](worktree-parallelism.md#viability-gate)). Whatever the smoke
run turns up goes to step 8.

### Spawning

Fill [agent-implementation.md](agent-implementation.md) per issue and spawn it as
`executor` -- or `architect` when the issue is foundational: blast radius, not
difficulty ([cost-discipline.md](cost-discipline.md#the-foundation-exception-architect-for-what-the-backlog-builds-on)).
A change small enough that the handoff costs more than the work is implemented here
([the floor](cost-discipline.md#the-floor-too-small-to-delegate)). In parallel mode issue
every spawn of the batch **in one message**, each with its own worktree path, never the
main checkout -- spawned one after another, they run one after another.

### Judging what came back

**Judge each result in this context**, against the issue and step 2b's decision:

| Returned field | Consumed |
|---|---|
| `ACCEPTANCE` | **Here, first.** A `not-met` line is work still owed. Sending it back costs one resume; letting it through merges a PR that closed an issue it did not answer. Green CI does not cover this -- it proves the repository still works, not that the issue was answered. |
| `UNRESOLVED` | **Here.** Judgment calls the agent made alone: each is accepted (and stated at step 10) or sent back, never silently inherited. |
| `CHANGED` | **Here.** A user-facing change -- anything a user of an app cut from this template would notice, or a change to the template's own documented surface -- owes a `CHANGELOG.md` entry under `[Unreleased]` (`AGENTS.md`'s "Review Checklist", item 5). No entry in `CHANGED` for such a change is work still owed, the same as a `not-met` line. |
| `PR-SUMMARY` / `TEST-PLAN` | [Step 4](pr-ci-merge.md#4-open-the-pr), verbatim. |
| `MEASURE` | [Step 5](#5-the-codex-review) -- what review findings are checked against. |
| `SCOPE-NOTES` / `FOLLOW-UPS` | Step 8 ([filing-followups.md](filing-followups.md)). |

`CHANGELOG.md` is an append-target file: two branches of one parallel batch that both
add an entry conflict on merge, which is why step 2c serializes them
([dependency-triage.md](dependency-triage.md#parallel-vs-sequential-all-mode)).

### Resuming a run

At most **2 resume runs** on top of the first; a third miss is `NEEDS-CLARIFICATION`,
not another spawn. A resume names only what is left.

**Reuse the agent that did the first run.** While it is still reachable, send the resume
to it with `SendMessage` and its agent ID: it already read the issue, the code, and its
own diff, and a new spawn would pay for all of that again from a cold start. Spawn a
fresh agent -- on the same tier as the first run -- only when that agent is gone, or when
its own context is what went wrong (it misread the issue and every later turn builds on
the misreading). A resume never changes tier: a foundational issue the first run got
half-right is exactly where the remaining judgment sits. Under Codex CLI there is no
`SendMessage` and no named tier: finish the resume inline in the main session.

A run that returned without a report, stopped before pushing, or missed or widened the
spec: [recovery.md](recovery.md). Never re-spawn an agent that returned without its
report -- its work is on disk.

## 5. The Codex review

### The single-review policy

This repository's GitHub integration has Codex review every pull request once, shortly
after it is opened (usually within a few minutes, almost always inside ten). That one
automatic review **is** this run's review. The owner chose it over a local pass, and the
choice has four consequences:

- **No local review runs**, before or after the PR opens -- no `/code-review`, no review
  sub-agent, no self-review presented as one. A missing or failed Codex review is
  reported, never replaced.
- **One review per PR.** Never post `@codex review` (or any other `@codex` request),
  never mark the PR draft and ready again, never close and reopen it, and never wait for
  a later review after pushing fixes. Pushes do not start a new automatic review.
- **Accepted findings are addressed once**, in one fix pass. The commits that fix them,
  and anything a later merge of the default branch brings in, get no fresh review: that
  is the accepted risk of this policy, and the step 10 report says so rather than
  presenting the final head as reviewed.
- **The review does not replace anything else.** CI on the current head, a required
  human review, and an unresolved correctness finding still gate the merge.

### Waiting for it

Open the PR first (step 4); then, before watching CI:

```bash
mkdir -p <runstate>/review
${CLAUDE_SKILL_DIR}/scripts/codex_review.py <pr> --timeout 600 > <runstate>/review/<pr>.log
grep -E '^(verdict|review_status|reviewed_commit|review_trigger|reviewed_head|findings|waited_seconds|detail):|^  F[0-9]' <runstate>/review/<pr>.log
```

The script reads only what `chatgpt-codex-connector[bot]` posted -- the
`<!-- codex-pull-request-review-summary -->` conversation comment whose table reports the
review's status and reviewed commit, the review's inline comments, and its +1 reaction --
and is the run's only wait primitive for it: **never a hand-rolled sleep/poll loop**. A
comment by anyone else, or one merely quoting the marker, counts for nothing.

The 600 s budget does not fit one foreground call (the Bash tool stops one at 600 s), so
wait the way step 6 waits for CI
([pr-ci-merge.md](pr-ci-merge.md#waiting-inside-the-600-second-cap)): in the background
with `--timeout 600` and its completion notification, or in the foreground with
`--timeout 540`, then once more for the remainder. CI is already running meanwhile; a
CI failure that surfaces while the review is pending may be diagnosed, but nothing is
pushed until the review has been read, so its findings and the CI repair land together.

### Reading the verdict

| `verdict:` | Next |
|---|---|
| `FINDINGS` | [Triage](#triage) every `F<n>` it lists. |
| `CLEAN` | Nothing to fix; `thumbs_up: yes` is the bot's own no-findings signal. Record it and go to step 6. |
| `TIMEOUT` | Not a verdict on the code. Under 600 s in total, wait again. Past it, hold the PR: record `--event blocked --field issue=<n> --field reason=codex-review-missing`, move to the next issue, and re-read it once with `--timeout 0` before step 9 -- completed by then, it resumes here. |
| `FAILED` | Hold the PR the same way with `reason=codex-review-failed`. |
| `ERROR` | GitHub could not be read: re-run once; then treat it as `TIMEOUT` past the budget. |

A held PR stays open with its branch: it is listed at step 10 for a human, and its
dependents are skipped like a FAILED issue's. `reviewed_head: no` on a first read means
a push landed before the review finished; the review still counts for this PR.
`review_trigger:` other than `PR opened` means someone asked for a review by hand --
read what is there, but do not wait for it.

### Triage

Read each finding in full before deciding anything:
`codex_review.py <pr> --timeout 0 --json > <runstate>/review/<pr>.json` carries every
body, and only the findings' bodies need reading, not the whole file. Number them as the
script does (`F1`, `F2`, ...) and keep those numbers through the fix.

Decide each one as **accepted**, **rejected**, or **out of scope**, with a reason:

- **Accepted** -- a real defect in this diff, or in the behavior the issue is about.
  "Belongs in this diff" is the same behavior change the issue is about, tests included
  -- a sibling case of the bug just fixed belongs here; a new Core port, a new public
  surface, or a new target does not, however small the patch looks
  ([filing-followups.md](filing-followups.md)).
- **Rejected** -- wrong on reading the code (it already handles the case, or the
  suggested behavior is not what the issue asks for). A P-badge is Codex's own severity,
  not a verdict: a `P1` can be wrong and a `P3` right.
- **Out of scope** -- real, but not this diff's: step 8 files it. A real correctness
  defect is never quietly dropped because it is out of scope.

An accepted correctness finding blocks the merge until it is fixed; green CI does not
dismiss it. A finding that needs a product or design decision this run cannot make holds
the PR (`reason=review-decision`) and goes to the step 10 report.

### Fixing the accepted findings once

**Serial:** apply them in the main checkout, which is on the branch. **Parallel:** in
the branch's own worktree, never the main checkout -- inline, or one
[agent-review-fix.md](agent-review-fix.md) per branch to `executor`, all spawned in one
message; a branch with zero accepted findings gets no spawn. A rejection sent back for
another try goes to the same fix agent by `SendMessage` while it is reachable.

When anything other than this session wrote the fix, **reading what it changed is the
safeguard**: `git -C <workdir> diff <pre-fix-commit>..HEAD`, not the whole branch.
Revert what it got wrong; read its `REJECTED` lines -- a rejection that reads like a real
defect goes back once with the reason addressed, and real-but-out-of-scope goes to step
8. Run `just check` **in `<workdir>`** when anything changed, commit, and push. That
push is the head step 6 watches.

This is the only fix pass the review gets. A CI failure afterwards is step 6's repair
loop, not a second review round.

### Recording it

Per PR: `--event review --field issue=<n> --field pr=<url> --field by=codex
--field reviewed=<reviewed_commit> --field verdict=<CLEAN|FINDINGS|TIMEOUT|FAILED>
--field findings=<n> --field accepted=<n> --field rejected=<n> --field fixed-in=<sha|none>`.
The step 10 report repeats it: the reviewed commit, each finding's disposition, the
commit that addressed the accepted ones, and that the final head was not re-reviewed.
