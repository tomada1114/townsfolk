#!/usr/bin/env bash
# Tests for scripts/clear-holding.sh: that it removes exactly the named holding
# directories, refuses any name that is not an issue number or `run` before deleting
# anything, and derives the state directory from `origin` the way shipping-issues does.
#
# Every case works in a throwaway state directory or repository under the temp root;
# the real ~/.local/state is never touched (AGENT_SKILL_STATE_DIR points elsewhere).
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

CLEAR_SH="${REPO_ROOT}/scripts/clear-holding.sh"

# make_state NAME... — a state directory whose holding/ holds one non-empty
# directory per NAME, plus a sibling file outside holding/ that must survive.
make_state() {
    local state name
    state=$(cd "$(make_temp_dir)" && pwd)
    mkdir -p "${state}/holding"
    for name in "$@"; do
        mkdir -p "${state}/holding/${name}/nested"
        echo "probe" >"${state}/holding/${name}/nested/probe.swift"
    done
    echo "keep" >"${state}/run.md"
    echo "${state}"
}

case_removes_only_the_named_holdings() {
    local state
    state=$(make_state 5 7 run)
    capture "${CLEAR_SH}" --state-dir "${state}" 5 run
    assert_exit 0
    [ ! -e "${state}/holding/5" ] || _fail "holding/5 survived"
    [ ! -e "${state}/holding/run" ] || _fail "holding/run survived"
    [ -d "${state}/holding/7" ] || _fail "holding/7 was removed"
    [ -d "${state}/holding" ] || _fail "holding/ itself was removed"
    [ -f "${state}/run.md" ] || _fail "run.md outside holding/ was removed"
    assert_stdout_contains "removed ${state}/holding/5"
}

case_a_missing_holding_is_a_notice() {
    local state
    state=$(make_state 5)
    capture "${CLEAR_SH}" --state-dir "${state}" 9
    assert_exit 0
    assert_stdout_contains "nothing held for '9'"
    [ -d "${state}/holding/5" ] || _fail "holding/5 was removed"
}

# A bad name anywhere in the list deletes nothing, including the good names before it.
case_refuses_a_path_shaped_name() {
    local state bad
    state=$(make_state 5)
    for bad in .. ../.. "5/.." "/" "*" "" "5x" "-r" "holding"; do
        capture "${CLEAR_SH}" --state-dir "${state}" 5 "${bad}"
        assert_exit 1
        assert_stderr_contains "ERR_HOLDING_USAGE"
        [ -d "${state}/holding/5" ] || _fail "holding/5 was removed alongside the bad name '${bad}'"
    done
}

case_refuses_no_name() {
    local state
    state=$(make_state 5)
    capture "${CLEAR_SH}" --state-dir "${state}"
    assert_exit 1
    assert_stderr_contains "ERR_HOLDING_USAGE"
}

case_rejects_a_bad_state_dir() {
    capture "${CLEAR_SH}" --state-dir "${CASE_DIR}/nope" 5
    assert_exit 1
    assert_stderr_contains "ERR_HOLDING_USAGE"
    capture "${CLEAR_SH}" --state-dir
    assert_exit 1
    assert_stderr_contains "ERR_HOLDING_USAGE"
}

# Without --state-dir the state directory is <AGENT_SKILL_STATE_DIR>/shipping-issues/
# <owner>__<repo>, with owner and repo read from origin (SSH and HTTPS forms).
case_derives_the_state_dir_from_origin() {
    local repo base url
    for url in git@github.com:acme/widget.git https://github.com/acme/widget; do
        repo=$(make_temp_repo)
        base=$(cd "$(make_temp_dir)" && pwd)
        git -C "${repo}" remote add origin "${url}"
        mkdir -p "${base}/shipping-issues/acme__widget/holding/12"
        (cd "${repo}" && AGENT_SKILL_STATE_DIR="${base}" capture "${CLEAR_SH}" 12 &&
            [ "${CAPTURED_EXIT}" = 0 ]) || _fail "exit was not 0 for origin ${url}"
        [ ! -e "${base}/shipping-issues/acme__widget/holding/12" ] ||
            _fail "holding/12 survived for origin ${url}"
    done
}

case_refuses_without_a_github_origin() {
    local repo
    repo=$(make_temp_repo)
    git -C "${repo}" remote add origin https://example.com/acme/widget.git
    cd "${repo}"
    AGENT_SKILL_STATE_DIR="${CASE_DIR}" capture "${CLEAR_SH}" 5
    assert_exit 1
    assert_stderr_contains "ERR_HOLDING_NO_ORIGIN"
    cd "$(make_temp_dir)"
    AGENT_SKILL_STATE_DIR="${CASE_DIR}" capture "${CLEAR_SH}" 5
    assert_exit 1
    assert_stderr_contains "ERR_HOLDING_NO_ORIGIN"
}

run_case "removes only the named holding directories" case_removes_only_the_named_holdings
run_case "a name with nothing held is a notice, not an error" case_a_missing_holding_is_a_notice
run_case "a path-shaped or non-numeric name is refused, and nothing is deleted" case_refuses_a_path_shaped_name
run_case "no name is refused" case_refuses_no_name
run_case "a missing or nonexistent --state-dir is refused" case_rejects_a_bad_state_dir
run_case "the state directory is derived from origin" case_derives_the_state_dir_from_origin
run_case "a non-GitHub origin or no repository is refused" case_refuses_without_a_github_origin
finish
