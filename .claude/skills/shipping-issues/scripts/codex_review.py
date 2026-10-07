#!/usr/bin/env python3
"""codex_review.py -- Wait for a PR's automatic Codex review and list its findings.

Step 4 of SKILL.md does not run a review of its own. This repository's GitHub
integration has Codex review every pull request once, shortly after it is opened,
and that one review is the run's review: the run waits for it, addresses the
findings it accepts once, and never asks for a second one. This script is the
wait and the read, so the caller never hand-rolls a sleep/poll loop.

What Codex posts, and what this script reads (all by the GitHub login
`chatgpt-codex-connector[bot]`, which no person can hold -- a GitHub username
cannot contain brackets -- so a display name, or anyone else's comment quoting
the marker, never counts):

  * a conversation comment carrying `<!-- codex-pull-request-review-summary -->`,
    created when the review is queued and edited in place as it runs. Its table
    has one row per review, `| Review | Status | Commit | Review trigger |`; a
    finished one reads `Completed` with the reviewed commit's short SHA. Only
    `Completed` is terminal success; a status naming a failure, an error, or a
    cancellation is terminal failure; anything else is still running.
  * with findings: a PR review whose inline comments each open with a priority
    badge (`![P1 Badge]`, ...) and a bold one-line title;
  * without findings: a +1 reaction on the PR and no inline comments.

Usage:
    codex_review.py <pr> [--timeout SECONDS] [--interval SECONDS]
                    [--repo OWNER/NAME] [--json]

--timeout bounds this call's wait (default 540, under a 600-second command cap;
0 reads once). The skill's budget is 900 s in total: one background call with
--timeout 900, or foreground calls of at most 540 s each until 900 s have passed.
--interval is the pause between reads (default 30).

Prints (key: value lines, then one line per finding):
    verdict: CLEAN | FINDINGS | TIMEOUT | FAILED | ERROR
    head_sha: <the PR's head commit when this ran>
    summary: present | absent
    review_status: <the summary's Status cell, plain text> | none
    reviewed_commit: <short SHA from the summary> | none
    review_trigger: <PR opened | Manual request | ...> | none
    reviewed_head: yes | no      (is the reviewed commit the current head)
    thumbs_up: yes | no          (the bot's +1 reaction on the PR)
    waited_seconds: <n>
    findings: <n>
      F<n> [P<k>] <path>:<line> (<commit>) -- <title>
    detail: <why>                (on anything but CLEAN or FINDINGS)

--json prints one object instead, finding bodies included; redirect it into
<runstate> rather than reading it into context.

Exit codes:
    0 = the review completed (CLEAN or FINDINGS)
    1 = the review reported a failure (FAILED)
    2 = still not completed when --timeout ran out (TIMEOUT) -- not a verdict
        on the code; read again, or report it
    3 = usage error
    4 = GitHub could not be read (ERROR)
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from typing import Any

# Run straight from the .claude/skills mirror, a __pycache__ would be written
# there, which `just agents-check` reports as drift.
sys.dont_write_bytecode = True

BOT_LOGIN = "chatgpt-codex-connector[bot]"
SUMMARY_MARKER = "<!-- codex-pull-request-review-summary -->"
FAILED_STATUS_RE = re.compile(r"(?i)\b(fail\w*|error\w*|cancel\w*|timed out)\b")
BADGE_RE = re.compile(r"!\[P(\d)\s+Badge\]")
IMAGE_RE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
SHORT_SHA_RE = re.compile(r"`([0-9a-fA-F]{7,40})`")


class GhError(Exception):
    """A `gh` call failed; the message is safe to print."""


def gh(args: list[str]) -> str:
    try:
        proc = subprocess.run(["gh", *args], capture_output=True, text=True,
                              encoding="utf-8", timeout=120)
    except FileNotFoundError as exc:
        raise GhError("gh CLI not found") from exc
    except subprocess.TimeoutExpired as exc:
        raise GhError(f"gh {' '.join(args[:4])} timed out") from exc
    if proc.returncode != 0:
        first = (proc.stderr.strip().splitlines() or ["no stderr"])[0]
        raise GhError(f"gh {' '.join(args[:4])} failed: {first}")
    return proc.stdout


def api_items(path: str) -> list[dict[str, Any]]:
    """Every item of a paginated REST list, read one JSON object per line so
    `--paginate`'s page-by-page arrays never have to be stitched together."""
    out = gh(["api", "--method", "GET", path, "--paginate", "--jq", ".[] | tojson"])
    items = []
    for line in out.splitlines():
        line = line.strip()
        if line:
            try:
                items.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise GhError(f"unreadable JSON from {path}") from exc
    return items


def from_bot(item: dict[str, Any]) -> bool:
    # The login, not `user.type`: GitHub reports the same app as `User` on a
    # reaction and as `Bot` on a comment.
    return (item.get("user") or {}).get("login") == BOT_LOGIN


def plain(cell: str) -> str:
    """A table cell as plain ASCII text: tags, emphasis and emoji dropped."""
    text = re.sub(r"<relative-time[^>]*>.*?</relative-time>", " ", cell)
    text = re.sub(r"<[^>]+>", " ", text)
    text = text.replace("**", "").replace("`", "")
    text = re.sub(r"[^\x20-\x7e]", " ", text)
    return " ".join(text.split())


def parse_summary(body: str) -> list[dict[str, str]]:
    """The summary table's review rows: name, status, commit, trigger."""
    rows = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("|") or set(line) <= set("|-: "):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 4 or plain(cells[0]).lower() == "review":
            continue
        commit = SHORT_SHA_RE.search(cells[2])
        rows.append({
            "review": plain(cells[0]),
            "status": plain(cells[1]),
            "commit": commit.group(1) if commit else "",
            "trigger": plain(cells[3]),
        })
    return rows


def code_review_row(rows: list[dict[str, str]]) -> dict[str, str] | None:
    """The `Code Review` row (a security review row is not the PR's review)."""
    for row in rows:
        if "code review" in row["review"].lower():
            return row
    return rows[0] if rows else None


def finding_from(comment: dict[str, Any]) -> dict[str, Any]:
    body = comment.get("body") or ""
    badge = BADGE_RE.search(body)
    # The title is the first non-empty line with the badge image dropped.
    first = next((ln for ln in body.splitlines() if ln.strip()), "")
    title = plain(IMAGE_RE.sub(" ", first))
    line = comment.get("line") or comment.get("original_line")
    return {
        "priority": f"P{badge.group(1)}" if badge else "P?",
        "path": comment.get("path") or "",
        "line": line,
        "commit": (comment.get("commit_id") or comment.get("original_commit_id") or "")[:7],
        "title": title[:160] or "(no title)",
        "url": comment.get("html_url") or "",
        "body": body,
    }


def read_state(pr: str, repo: str | None) -> dict[str, Any]:
    base = f"repos/{repo}" if repo else "repos/{owner}/{repo}"
    view = ["pr", "view", pr, "--json", "headRefOid,state"]
    if repo:
        view += ["--repo", repo]
    try:
        head = json.loads(gh(view) or "{}")
    except json.JSONDecodeError as exc:
        raise GhError(f"unreadable JSON from gh pr view {pr}") from exc
    comments = [c for c in api_items(f"{base}/issues/{pr}/comments")
                if from_bot(c) and SUMMARY_MARKER in (c.get("body") or "")]
    state: dict[str, Any] = {
        "head_sha": head.get("headRefOid") or "",
        "pr_state": head.get("state") or "",
        "summary": "present" if comments else "absent",
        "review_status": "none", "reviewed_commit": "none",
        "review_trigger": "none", "status_kind": "pending",
    }
    if comments:
        # The newest summary wins if the bot ever posted a second one.
        latest = max(comments, key=lambda c: (c.get("created_at") or "", c.get("id") or 0))
        row = code_review_row(parse_summary(latest.get("body") or ""))
        if row:
            state["review_status"] = row["status"] or "none"
            state["reviewed_commit"] = row["commit"] or "none"
            state["review_trigger"] = row["trigger"] or "none"
            if re.search(r"(?i)\bcompleted\b", row["status"]):
                state["status_kind"] = "completed"
            elif FAILED_STATUS_RE.search(row["status"]):
                state["status_kind"] = "failed"
    if state["status_kind"] != "completed":
        return state

    inline = [c for c in api_items(f"{base}/pulls/{pr}/comments")
              if from_bot(c) and not c.get("in_reply_to_id")]
    reviews = [r for r in api_items(f"{base}/pulls/{pr}/reviews") if from_bot(r)]
    findings = [finding_from(c) for c in
                sorted(inline, key=lambda c: (c.get("created_at") or "", c.get("id") or 0))]
    # A finding Codex could not anchor to a line lands in the review body.
    findings += [finding_from(r) for r in reviews if BADGE_RE.search(r.get("body") or "")]
    reactions = api_items(f"{base}/issues/{pr}/reactions")
    state["thumbs_up"] = any(from_bot(r) and r.get("content") == "+1" for r in reactions)
    state["findings"] = findings
    return state


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("pr", help="pull request number")
    p.add_argument("--timeout", type=int, default=540,
                   help="seconds to wait for the review in total (0 = read once)")
    p.add_argument("--interval", type=int, default=30,
                   help="seconds between reads")
    p.add_argument("--repo", metavar="OWNER/NAME",
                   help="the repository; default: the one gh resolves from cwd")
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args(argv)
    pr = args.pr.lstrip("#")
    if not pr.isdigit() or args.timeout < 0 or args.interval < 0:
        print("error: <pr> must be a number and --timeout/--interval >= 0",
              file=sys.stderr)
        return 3
    if args.repo and not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo):
        print(f"error: --repo must look like OWNER/NAME, got: {args.repo!r}",
              file=sys.stderr)
        return 3

    start = time.monotonic()
    while True:
        try:
            state = read_state(pr, args.repo)
        except GhError as exc:
            return report({"verdict": "ERROR", "detail": str(exc)},
                          int(time.monotonic() - start), args.as_json)
        waited = int(time.monotonic() - start)
        if state["status_kind"] == "completed":
            state["verdict"] = "FINDINGS" if state["findings"] else "CLEAN"
            return report(state, waited, args.as_json)
        if state["status_kind"] == "failed":
            state["verdict"] = "FAILED"
            state["detail"] = (f"the Codex review reported `{state['review_status']}`; "
                               "report it -- never stand a local review in for it")
            return report(state, waited, args.as_json)
        if state["pr_state"] and state["pr_state"] != "OPEN":
            state["verdict"] = "ERROR"
            state["detail"] = f"PR #{pr} is {state['pr_state']}, not OPEN"
            return report(state, waited, args.as_json)
        if waited + args.interval > args.timeout:
            state["verdict"] = "TIMEOUT"
            state["detail"] = ("no Codex summary comment on this PR yet"
                               if state["summary"] == "absent" else
                               f"the Codex review is still `{state['review_status']}`")
            return report(state, waited, args.as_json)
        time.sleep(args.interval)


EXIT = {"CLEAN": 0, "FINDINGS": 0, "FAILED": 1, "TIMEOUT": 2, "ERROR": 4}


def report(state: dict[str, Any], waited: int, as_json: bool) -> int:
    state["waited_seconds"] = waited
    findings = state.get("findings", [])
    head = state.get("head_sha", "")
    reviewed = state.get("reviewed_commit", "none")
    state["reviewed_head"] = bool(head and reviewed != "none"
                                  and head.lower().startswith(reviewed.lower()))
    if as_json:
        state.pop("status_kind", None)
        print(json.dumps(state, ensure_ascii=True, indent=2))
        return EXIT[state["verdict"]]
    print(f"verdict: {state['verdict']}")
    for key in ("head_sha", "summary", "review_status", "reviewed_commit",
                "review_trigger"):
        if key in state:
            print(f"{key}: {state[key]}")
    if "summary" in state:
        print(f"reviewed_head: {'yes' if state['reviewed_head'] else 'no'}")
    if "thumbs_up" in state:
        print(f"thumbs_up: {'yes' if state['thumbs_up'] else 'no'}")
    print(f"waited_seconds: {waited}")
    if state["verdict"] in ("CLEAN", "FINDINGS"):
        print(f"findings: {len(findings)}")
        for n, f in enumerate(findings, start=1):
            where = f"{f['path']}:{f['line']}" if f["path"] else "(review body)"
            print(f"  F{n} [{f['priority']}] {where} ({f['commit'] or '?'}) -- {f['title']}")
    if state.get("detail"):
        print(f"detail: {state['detail']}")
    return EXIT[state["verdict"]]


if __name__ == "__main__":
    sys.exit(main())
