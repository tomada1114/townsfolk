# Run record

The persistent log every step appends to, read when setting up `<runstate>` or
auditing what a stopped run already landed.

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/run_record.py --repo <owner>/<repo> --event <kind> \
    [--field k=v ...] [--body-file <path>]
```

Appends one line (or, for `run-start`, a heading plus a line) to `<runstate>/run.md`,
where **`<runstate>`** is
`${AGENT_SKILL_STATE_DIR:-$HOME/.local/state/agent-skills}/shipping-issues/<owner>__<repo>/`
-- never rewritten or deleted, so a stopped run keeps what already landed. A leading
`~` in `AGENT_SKILL_STATE_DIR` is expanded by every script. `preflight.sh` and
`issue_digest.py` read `<owner>/<repo>` from the origin URL identically -- git's
scp-style `[user@]host:[/]owner/repo` (a bare ssh host alias too) or `https`, `http`,
`ssh`, `git`, `git+ssh`, `ssh+git` as `scheme://[user@]host[:port]/owner/repo`, `.git`
and a trailing `/` optional; anything else, `file://` included, is `UNKNOWN` -- and
`scripts/tests/test_runstate_parity.py` holds them equal. `run_record.py` instead
takes `--repo` or asks `gh repo view` (as do `file_followup.py` and `link_check.sh`).

Every other file this run generates lives there too, and **never inside a
repo checkout** -- the main one or a worktree: issue bodies for follow-ups,
verify baselines at `<runstate>/verify/<n>-baseline.log`, CI logs at
`<runstate>/ci/<pr>.log`, in parallel mode the worktrees themselves at
`<runstate>/worktrees/<n>/`, and whatever was moved out of the way instead of
deleted at `<runstate>/holding/<n>/`, with approval-gated commands put off
until the end in `<runstate>/deferred.md`
([closing-out.md#approval-gated-commands](closing-out.md#approval-gated-commands)). An untracked file left in a checkout makes that
working tree read as dirty, and a commit convention that stages everything
would land it in the PR. Call it right after the event happens, not batched at
the end; `--repo` can be omitted when cwd is the repo being shipped.

Events: `run-start`, `selection` (the rubric-shaped block from
priority-rubric.md via `--body-file`), `labels`, `design`, `parallel-group`,
`pr-created`, `review`, `ci`, `merged`, `followup`, `cleanup`, `blocked`,
`note`.

`design` records a settled -- or deliberately deferred -- design, from either
path: `--field issue=<n> --field step=<2b|8b> --field mode=<inline|background>
--field verdict=<DECIDED|DEFERRED>`. `step` tells a step 2b decision (the design
gating the issue being implemented) from a step 8b one. A `DEFERRED` line is the
more valuable of the two to read back: it is a question waiting on a human, and
the label still says blocked.

`review` records one Codex review round of a PR once its findings are answered
(`--field round=<k>`, [implement-and-review.md](implement-and-review.md#fixing-the-accepted-findings)); after
a context compaction, the `review` lines for a PR say which rounds not to wait for, or
fix against, again. `blocked` carries the reason a PR is held: `no-review`,
`review-error`, `review-finding`, `review-cap`, `review-required`, `not-linked`,
`linear-history`, `merge-conflict`.

`parallel-group` records the plan's grouping decision once per batch (plan.py
--record writes it) --
`--field issues=<n,m,...> --field mode=<parallel|serial> --field reason=<why>`.
A serial fallback is recorded the same way as a parallel batch: the reason a
run did *not* parallelize is the part worth being able to read back.
