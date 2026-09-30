#!/usr/bin/env bash
# Tests for scripts/reset-permissions.sh: that it resets exactly the identifier
# project.yml declares, and the named failure for each way it can refuse.
#
# `tccutil` is always stubbed — no real permission grant is ever dropped, on this
# machine or any other — and every case reads a throwaway project.yml under --root,
# never the real checkout's.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

RESET_SH="${REPO_ROOT}/scripts/reset-permissions.sh"

# make_fixture_root [IDENTIFIER] — a directory holding a project.yml that declares
# IDENTIFIER (com.example.MyApp by default); with the empty string, none at all.
make_fixture_root() {
    local root identifier="${1-com.example.MyApp}"
    root=$(cd "$(make_temp_dir)" && pwd)
    {
        echo "name: MyApp"
        echo "targets:"
        echo "  MyApp:"
        echo "    type: application"
        echo "    settings:"
        echo "      base:"
        [ -z "${identifier}" ] || echo "        PRODUCT_BUNDLE_IDENTIFIER: ${identifier}"
    } >"${root}/project.yml"
    echo "${root}"
}

# assert_tccutil_called_with ARGS — the one and only tccutil call had ARGS.
assert_tccutil_called_with() {
    local log="${STUB_BIN}/tccutil.log"
    [ -f "${log}" ] || _fail "tccutil was never called"
    [ "$(cat "${log}")" = "$1" ] || _fail "tccutil was called with: $(cat "${log}")"
}

# assert_tccutil_not_called — nothing was reset.
assert_tccutil_not_called() {
    [ ! -f "${STUB_BIN}/tccutil.log" ] || _fail "tccutil was called: $(cat "${STUB_BIN}/tccutil.log")"
}

case_resets_the_declared_identifier() {
    local root
    root=$(make_fixture_root)
    stub_command tccutil 'exit 0'
    capture "${RESET_SH}" --root "${root}"
    assert_exit 0
    assert_tccutil_called_with "reset All com.example.MyApp"
    assert_stdout_contains "com.example.MyApp"
}

# The identifier comes from the manifest, so a bootstrapped app resets its own.
case_follows_a_renamed_manifest() {
    local root
    root=$(make_fixture_root com.acme.Widget)
    stub_command tccutil 'exit 0'
    capture "${RESET_SH}" --root "${root}"
    assert_exit 0
    assert_tccutil_called_with "reset All com.acme.Widget"
}

case_reports_a_failing_tccutil() {
    local root
    root=$(make_fixture_root)
    stub_command tccutil 'exit 3'
    capture "${RESET_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_RESET_FAILED"
    assert_stderr_contains "Next:"
}

# tccutil ships with macOS, so its absence is simulated by a PATH that holds only
# what the script needs before it looks for tccutil at all: the bash its shebang
# resolves through `env`, and the one `dirname` call above that check.
case_reports_a_missing_tccutil() {
    local root bin tool
    root=$(make_fixture_root)
    bin="${CASE_DIR}/bare-bin"
    mkdir -p "${bin}"
    for tool in bash dirname; do
        ln -s "$(command -v "${tool}")" "${bin}/${tool}"
    done
    PATH="${bin}" capture "${RESET_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_RESET_TOOL_MISSING"
}

case_rejects_an_unknown_argument() {
    local root
    root=$(make_fixture_root)
    stub_command tccutil 'exit 0'
    capture "${RESET_SH}" --root "${root}" com.somebody.Else
    assert_exit 1
    assert_stderr_contains "ERR_RESET_USAGE"
    assert_tccutil_not_called
}

case_rejects_a_bad_root() {
    stub_command tccutil 'exit 0'
    capture "${RESET_SH}" --root "${CASE_DIR}/nope"
    assert_exit 1
    assert_stderr_contains "ERR_RESET_USAGE"
    assert_tccutil_not_called
    capture "${RESET_SH}" --root
    assert_exit 1
    assert_stderr_contains "ERR_RESET_USAGE"
    assert_tccutil_not_called
}

case_resets_nothing_without_an_identifier() {
    local root
    root=$(make_fixture_root "")
    stub_command tccutil 'exit 0'
    capture "${RESET_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_BUNDLEID_NOT_FOUND"
    assert_tccutil_not_called
}

run_case "resets the identifier project.yml declares" case_resets_the_declared_identifier
run_case "follows a renamed manifest" case_follows_a_renamed_manifest
run_case "a failing tccutil is reported as ERR_RESET_FAILED" case_reports_a_failing_tccutil
run_case "a missing tccutil is reported as ERR_RESET_TOOL_MISSING" case_reports_a_missing_tccutil
run_case "an extra argument is refused, and nothing is reset" case_rejects_an_unknown_argument
run_case "a missing or nonexistent --root is refused" case_rejects_a_bad_root
run_case "a manifest with no identifier resets nothing" case_resets_nothing_without_an_identifier
finish
