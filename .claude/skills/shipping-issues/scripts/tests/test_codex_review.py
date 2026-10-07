#!/usr/bin/env python3
"""Tests for codex_review.py. Stdlib-only (unittest).

Run: python3 -m unittest discover -s scripts/tests -p 'test_*.py'
     (from the shipping-issues skill directory)
"""
from __future__ import annotations

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from _fakegh import FakeGh  # noqa: E402
import codex_review as cr  # noqa: E402

PR = "62"
HEAD = "b2783555a69aa39df5c2e72c4ee607b48f9e6923"
BOT = {"login": "chatgpt-codex-connector[bot]", "type": "Bot"}
HUMAN = {"login": "tomada1114", "type": "User"}


def VIEW(pr=PR):
    return ("pr", "view", pr, "--json", "headRefOid,state")


def API(path):
    return ("api", "--method", "GET", path)


def ISSUE_COMMENTS(pr=PR, base="repos/{owner}/{repo}"):
    return API(f"{base}/issues/{pr}/comments")


def REVIEW_COMMENTS(pr=PR, base="repos/{owner}/{repo}"):
    return API(f"{base}/pulls/{pr}/comments")


def REVIEWS(pr=PR, base="repos/{owner}/{repo}"):
    return API(f"{base}/pulls/{pr}/reviews")


def REACTIONS(pr=PR, base="repos/{owner}/{repo}"):
    return API(f"{base}/issues/{pr}/reactions")


def lines(*items):
    """What `gh api --paginate --jq '.[] | tojson'` prints: one object a line."""
    return "".join(json.dumps(i) + "\n" for i in items)


def summary(status="\u2705 **Completed** <relative-time datetime=\"x\">x</relative-time>",
            commit="b278355", trigger="PR opened", extra_rows=(), user=BOT, created="2026-10-07T20:41:57Z"):
    rows = [f"| \U0001F4DD **Code Review** | {status} | `{commit}` | {trigger} |", *extra_rows]
    body = ("<!-- codex-pull-request-review-summary -->\n\n## Codex Review Summary\n\n"
            "| Review | Status | Commit | Review trigger |\n| --- | --- | --- | --- |\n"
            + "\n".join(rows) + "\n\n<details>about</details>")
    return {"id": 1, "user": user, "created_at": created, "body": body}


def inline(cid, title, *, priority="P2", path="Sources/A.swift", line=10,
           created="2026-10-07T20:46:27Z", user=BOT, reply_to=None):
    return {
        "id": cid, "user": user, "created_at": created, "path": path, "line": line,
        "commit_id": HEAD, "in_reply_to_id": reply_to, "html_url": f"https://x/{cid}",
        "body": (f"**<sub><sub>![{priority} Badge](https://img.shields.io/badge/"
                 f"{priority}-yellow?style=flat)</sub></sub>  {title}**\n\nWhy it matters.\n"),
    }


def view(head=HEAD, state="OPEN"):
    return json.dumps({"headRefOid": head, "state": state})


class FakeClock:
    """Stands in for the `time` module: sleep() advances monotonic()."""

    def __init__(self):
        self.now = 0.0
        self.sleeps: list[float] = []

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


def run(argv, responses, *, sequences=None, exits=None, stderrs=None):
    clock = FakeClock()
    out, err = io.StringIO(), io.StringIO()
    with FakeGh(responses, sequences=sequences, exits=exits, stderrs=stderrs) as fake:
        with patch.dict(os.environ, fake.env, clear=False), \
                patch.object(cr, "time", clock), \
                redirect_stdout(out), redirect_stderr(err):
            rc = cr.main(argv)
        calls = list(fake.calls)
    return rc, out.getvalue(), err.getvalue(), calls, clock


def completed(*, comments=(), reviews=(), reactions=(), summary_items=None):
    return {
        VIEW(): view(),
        ISSUE_COMMENTS(): lines(*(summary_items if summary_items is not None else [summary()])),
        REVIEW_COMMENTS(): lines(*comments),
        REVIEWS(): lines(*reviews),
        REACTIONS(): lines(*reactions),
    }


class CompletedReviewTest(unittest.TestCase):
    def test_findings_are_numbered_in_order_with_badge_path_and_title(self):
        rc, out, _, calls, clock = run([PR], completed(comments=[
            inline(2, "Second finding", priority="P1", created="2026-10-07T20:46:28Z"),
            inline(1, "First finding", path="Sources/B.swift", line=46),
        ]))
        self.assertEqual(rc, 0)
        self.assertIn("verdict: FINDINGS\n", out)
        self.assertIn("review_status: Completed\n", out)
        self.assertIn("reviewed_commit: b278355\n", out)
        self.assertIn("review_trigger: PR opened\n", out)
        self.assertIn("reviewed_head: yes\n", out)
        self.assertIn("findings: 2\n", out)
        self.assertIn("  F1 [P2] Sources/B.swift:46 (b278355) -- First finding\n", out)
        self.assertIn("  F2 [P1] Sources/A.swift:10 (b278355) -- Second finding\n", out)
        self.assertEqual(clock.sleeps, [])
        # Every GitHub call is a read.
        self.assertTrue(all(c[0] in ("pr", "api") for c in calls))
        self.assertTrue(all(c[1:3] == ["--method", "GET"] for c in calls if c[0] == "api"))
        self.assertTrue(all(c[1] == "view" for c in calls if c[0] == "pr"))

    def test_clean_review_reports_the_thumbs_up(self):
        # GitHub reports the app as `User` on a reaction, `Bot` on a comment.
        rc, out, _, _, _ = run([PR], completed(reactions=[
            {"content": "+1", "user": {"login": BOT["login"], "type": "User"}},
        ]))
        self.assertEqual(rc, 0)
        self.assertIn("verdict: CLEAN\n", out)
        self.assertIn("findings: 0\n", out)
        self.assertIn("thumbs_up: yes\n", out)

    def test_replies_and_other_peoples_comments_are_not_findings(self):
        rc, out, _, _, _ = run([PR], completed(
            comments=[inline(1, "Real one"),
                      inline(2, "A reply", reply_to=1),
                      inline(3, "A human note", user=HUMAN)],
            reactions=[{"content": "+1", "user": HUMAN}],
        ))
        self.assertEqual(rc, 0)
        self.assertIn("findings: 1\n", out)
        self.assertIn("-- Real one\n", out)
        self.assertNotIn("A reply", out)
        self.assertNotIn("A human note", out)
        self.assertIn("thumbs_up: no\n", out)

    def test_a_finding_in_the_review_body_counts(self):
        body_finding = {"id": 9, "user": BOT, "commit_id": HEAD,
                        "body": "**![P1 Badge](u) Unanchored finding**\n\ntext"}
        plain_review = {"id": 8, "user": BOT, "commit_id": HEAD,
                        "body": "### Codex Review\n\nHere are some suggestions."}
        rc, out, _, _, _ = run([PR], completed(reviews=[plain_review, body_finding]))
        self.assertEqual(rc, 0)
        self.assertIn("findings: 1\n", out)
        self.assertIn("  F1 [P1] (review body) (b278355) -- Unanchored finding\n", out)

    def test_a_moved_head_is_reported_not_hidden(self):
        responses = completed()
        responses[VIEW()] = view(head="1234567" + "0" * 33)
        rc, out, _, _, _ = run([PR], responses)
        self.assertEqual(rc, 0)
        self.assertIn("reviewed_head: no\n", out)

    def test_the_code_review_row_wins_over_a_security_review_row(self):
        security = "| \U0001F512 **Security Review** | Running | `aaaaaaa` | Manual request |"
        responses = completed(summary_items=[summary(extra_rows=[security])])
        rc, out, _, _, _ = run([PR], responses)
        self.assertEqual(rc, 0)
        self.assertIn("review_status: Completed\n", out)
        self.assertIn("reviewed_commit: b278355\n", out)

    def test_a_completed_security_review_alone_is_not_the_code_review(self):
        security = summary()
        security["body"] = security["body"].replace(
            "\U0001F4DD **Code Review**", "\U0001F512 **Security Review**")
        responses = completed(summary_items=[security])
        rc, out, _, calls, clock = run([PR, "--timeout", "60", "--interval", "30"], responses)
        self.assertEqual(rc, 2)
        self.assertIn("verdict: TIMEOUT\n", out)
        self.assertIn("summary: present\n", out)
        self.assertIn("review_status: none\n", out)
        self.assertIn("detail: the Codex summary has no Code Review row yet\n", out)
        self.assertEqual(clock.sleeps, [30, 30])
        # Findings are never read for a review that is not the code review.
        self.assertEqual([c for c in calls if c[3:4] == [REVIEW_COMMENTS()[3]]], [])

    def test_with_both_rows_the_code_review_row_decides(self):
        security = "| \U0001F512 **Security Review** | \u2705 **Completed** | `aaaaaaa` | Manual request |"
        responses = completed(summary_items=[summary(status="Running", extra_rows=[security])])
        rc, out, _, _, _ = run([PR, "--timeout", "0"], responses)
        self.assertEqual(rc, 2)
        self.assertIn("review_status: Running\n", out)
        self.assertIn("reviewed_commit: b278355\n", out)

    def test_json_carries_the_finding_bodies(self):
        rc, out, _, _, _ = run([PR, "--json"], completed(comments=[inline(1, "Title")]))
        self.assertEqual(rc, 0)
        data = json.loads(out)
        self.assertEqual(data["verdict"], "FINDINGS")
        self.assertIn("Why it matters.", data["findings"][0]["body"])
        self.assertTrue(data["reviewed_head"])
        self.assertNotIn("status_kind", data)

    def test_explicit_repo_is_used_for_every_call(self):
        base = "repos/acme/widgets"
        responses = {
            ("pr", "view", PR, "--json", "headRefOid,state", "--repo", "acme/widgets"): view(),
            ISSUE_COMMENTS(base=base): lines(summary()),
            REVIEW_COMMENTS(base=base): "",
            REVIEWS(base=base): "",
            REACTIONS(base=base): "",
        }
        rc, out, _, calls, _ = run([PR, "--repo", "acme/widgets"], responses)
        self.assertEqual(rc, 0, out)
        self.assertIn("verdict: CLEAN\n", out)
        self.assertTrue(all("{owner}" not in " ".join(c) for c in calls))


class WaitingTest(unittest.TestCase):
    def test_waits_until_the_summary_reports_completed(self):
        running = summary(status="Running")
        responses = completed()
        sequences = {ISSUE_COMMENTS(): ["", lines(running), lines(summary())]}
        rc, out, _, calls, clock = run([PR, "--timeout", "900", "--interval", "30"],
                                       responses, sequences=sequences)
        self.assertEqual(rc, 0)
        self.assertIn("verdict: CLEAN\n", out)
        self.assertEqual(clock.sleeps, [30, 30])
        self.assertIn("waited_seconds: 60\n", out)
        # Findings are read only once the review has completed.
        self.assertEqual(len([c for c in calls if c[3:4] == [REVIEW_COMMENTS()[3]]]), 1)

    def test_timeout_without_a_summary_says_so(self):
        responses = completed(summary_items=[])
        rc, out, _, _, clock = run([PR, "--timeout", "60", "--interval", "30"], responses)
        self.assertEqual(rc, 2)
        self.assertIn("verdict: TIMEOUT\n", out)
        self.assertIn("summary: absent\n", out)
        self.assertIn("detail: no Codex summary comment on this PR yet\n", out)
        self.assertEqual(clock.sleeps, [30, 30])
        self.assertNotIn("findings:", out)

    def test_timeout_while_running_names_the_status(self):
        responses = completed(summary_items=[summary(status="Running")])
        rc, out, _, _, _ = run([PR, "--timeout", "30", "--interval", "30"], responses)
        self.assertEqual(rc, 2)
        self.assertIn("review_status: Running\n", out)
        self.assertIn("detail: the Codex review is still `Running`\n", out)

    def test_timeout_zero_reads_once(self):
        responses = completed(summary_items=[])
        rc, out, _, calls, clock = run([PR, "--timeout", "0"], responses)
        self.assertEqual(rc, 2)
        self.assertEqual(clock.sleeps, [])
        self.assertEqual(len([c for c in calls if c[:2] == ["pr", "view"]]), 1)

    def test_a_marker_from_anyone_but_the_bot_is_ignored(self):
        impostor = summary(user={"login": "chatgpt-codex-connector", "type": "User"})
        responses = completed(summary_items=[impostor])
        rc, out, _, _, _ = run([PR, "--timeout", "0"], responses)
        self.assertEqual(rc, 2)
        self.assertIn("summary: absent\n", out)

    def test_a_closed_pr_without_a_finished_review_is_an_error(self):
        responses = completed(summary_items=[])
        responses[VIEW()] = view(state="MERGED")
        rc, out, _, _, clock = run([PR, "--timeout", "900"], responses)
        self.assertEqual(rc, 4)
        self.assertIn("verdict: ERROR\n", out)
        self.assertIn("is MERGED, not OPEN", out)
        self.assertEqual(clock.sleeps, [])


class FailureTest(unittest.TestCase):
    def test_a_failed_review_is_reported(self):
        responses = completed(summary_items=[summary(status="\u274c **Failed**")])
        rc, out, _, _, clock = run([PR, "--timeout", "900"], responses)
        self.assertEqual(rc, 1)
        self.assertIn("verdict: FAILED\n", out)
        self.assertIn("never stand a local review in for it", out)
        self.assertEqual(clock.sleeps, [])

    def test_gh_failure_is_an_error(self):
        responses = completed()
        rc, out, _, _, _ = run([PR], responses, exits={ISSUE_COMMENTS(): 1},
                               stderrs={ISSUE_COMMENTS(): "HTTP 502: Bad Gateway\n"})
        self.assertEqual(rc, 4)
        self.assertIn("verdict: ERROR\n", out)
        self.assertIn("HTTP 502", out)

    def test_unreadable_json_is_an_error(self):
        responses = completed()
        responses[ISSUE_COMMENTS()] = "{not json\n"
        rc, out, _, _, _ = run([PR], responses)
        self.assertEqual(rc, 4)
        self.assertIn("unreadable JSON", out)

    def test_usage_errors(self):
        for argv in (["abc"], [PR, "--timeout", "-1"], [PR, "--repo", "a/b/c"]):
            with self.subTest(argv=argv):
                rc, _, err, calls, _ = run(argv, {})
                self.assertEqual(rc, 3)
                self.assertIn("error:", err)
                self.assertEqual(calls, [])


class ParseTest(unittest.TestCase):
    def test_plain_drops_tags_emphasis_and_emoji(self):
        cell = "\u2705 **Completed** <relative-time datetime=\"t\">t</relative-time>"
        self.assertEqual(cr.plain(cell), "Completed")

    def test_parse_summary_skips_the_header_and_separator(self):
        rows = cr.parse_summary(summary()["body"])
        self.assertEqual(rows, [{"review": "Code Review", "status": "Completed",
                                 "commit": "b278355", "trigger": "PR opened"}])


if __name__ == "__main__":
    unittest.main()
