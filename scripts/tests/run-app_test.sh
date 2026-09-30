#!/usr/bin/env bash
# Tests for scripts/run-app.sh: which running process it quits, which it leaves
# alone, and the named failure for each way relaunching can fail.
#
# No real app is ever quit or launched. `ps`, `plutil`, and `open` are stubbed,
# so the process table the script sees is written by the test; the one process
# it really signals is a detached `sleep` the test spawned for that purpose. The
# `plutil` stub prints the fixture bundle's Info.plist verbatim, so each fake
# bundle's identifier is just the contents of that file.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

RUN_APP_SH="${REPO_ROOT}/scripts/run-app.sh"
APP_RELATIVE_PATH="build/dev-derived-data/Build/Products/Debug/MyApp.app"

# make_fixture_root [--no-app] — a checkout-shaped directory: a project.yml
# declaring com.example.MyApp, and (unless --no-app) a built Debug app bundle.
make_fixture_root() {
    local root
    # Normalized (no doubled slash from TMPDIR), the way the script resolves it.
    root=$(cd "$(make_temp_dir)" && pwd)
    cat >"${root}/project.yml" <<'EOF'
name: MyApp
targets:
  MyApp:
    type: application
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyApp
EOF
    if [ "${1:-}" != "--no-app" ]; then
        mkdir -p "${root}/${APP_RELATIVE_PATH}/Contents/MacOS"
    fi
    echo "${root}"
}

# make_fixture_bundle NAME IDENTIFIER — a fake .app whose Info.plist the plutil
# stub reads; prints the executable path to put in the process table.
make_fixture_bundle() {
    local bundle="${CASE_DIR}/procs/$1.app"
    mkdir -p "${bundle}/Contents/MacOS"
    echo "$2" >"${bundle}/Contents/Info.plist"
    echo "${bundle}/Contents/MacOS/$1"
}

# spawn_detached SNIPPET — runs SNIPPET in the background of a shell that exits
# immediately, so the process is reparented and this test never reaps it (a
# zombie child would still answer `kill -0`). Prints its pid.
spawn_detached() {
    local pidfile="${CASE_DIR}/spawned.pid"
    bash -c "$1 >/dev/null 2>&1 & printf '%s' \$! >'${pidfile}'"
    cat "${pidfile}"
}

# stub_process_table BEFORE AFTER — the `ps` stub answers BEFORE until the `open`
# stub has run, then AFTER: one launch, two process tables.
stub_process_table() {
    printf '%s\n' "$1" >"${CASE_DIR}/ps.before"
    printf '%s\n' "$2" >"${CASE_DIR}/ps.after"
    stub_command ps "if [ -f '${CASE_DIR}/launched' ]; then cat '${CASE_DIR}/ps.after'; else cat '${CASE_DIR}/ps.before'; fi"
    # shellcheck disable=SC2016 # $4 is the stub's own argument, expanded at run time
    stub_command plutil 'cat "$4" 2>/dev/null || exit 1'
}

stub_open() { # stub_open [EXIT_CODE]
    stub_command open "touch '${CASE_DIR}/launched'; exit ${1:-0}"
}

assert_open_called_with() {
    grep -qF -- "$1" "${STUB_BIN}/open.log" || _fail "open was not called with: $1"
}

assert_open_not_called() {
    [ ! -e "${STUB_BIN}/open.log" ] || _fail "open was called, and should not have been"
}

assert_pid_gone() {
    ! kill -0 "$1" 2>/dev/null || _fail "pid $1 is still running"
}

assert_pid_alive() {
    kill -0 "$1" 2>/dev/null || _fail "pid $1 was killed, and should not have been"
}

case_quits_then_launches() {
    root=$(make_fixture_root)
    executable=$(make_fixture_bundle MyApp com.example.MyApp)
    pid=$(spawn_detached 'sleep 30')
    stub_process_table "  1 /sbin/launchd
  ${pid} ${executable}" "  4242 ${executable}"
    stub_open

    capture "${RUN_APP_SH}" --root "${root}"
    assert_exit 0
    assert_pid_gone "${pid}"
    assert_stdout_contains "Quitting com.example.MyApp (pid ${pid})"
    assert_stdout_contains "com.example.MyApp is running (pid 4242)"
    assert_open_called_with "${root}/${APP_RELATIVE_PATH}"
    grep -qF "CFBundleIdentifier" "${STUB_BIN}/plutil.log" ||
        _fail "the bundle identifier was never read from a running app's Info.plist"
}

case_launches_when_nothing_is_running() {
    root=$(make_fixture_root)
    other=$(make_fixture_bundle Safari com.apple.Safari)
    ours=$(make_fixture_bundle MyApp com.example.MyApp)
    stub_process_table "  1 /sbin/launchd
  321 ${other}" "  321 ${other}
  4242 ${ours}"
    stub_open

    capture "${RUN_APP_SH}" --root "${root}"
    assert_exit 0
    assert_stdout_not_contains "Quitting" "a quit step"
    assert_open_called_with "${root}/${APP_RELATIVE_PATH}"
}

case_leaves_a_same_named_app_alone() {
    # The point of matching by bundle identifier: another app whose executable is
    # named MyApp — a build of the template from a different checkout — is not
    # this app, and a name match would have quit it.
    root=$(make_fixture_root)
    executable=$(make_fixture_bundle MyApp com.other.MyApp)
    ours=$(make_fixture_bundle Ours com.example.MyApp)
    pid=$(spawn_detached 'sleep 30')
    stub_process_table "  ${pid} ${executable}" "  ${pid} ${executable}
  4242 ${ours}"
    stub_open

    capture "${RUN_APP_SH}" --root "${root}"
    assert_exit 0
    assert_pid_alive "${pid}"
    assert_stdout_not_contains "Quitting" "a quit step"
    assert_open_called_with "${root}/${APP_RELATIVE_PATH}"
    kill -9 "${pid}" 2>/dev/null || true
}

case_survivor_is_reported_not_forced() {
    root=$(make_fixture_root)
    executable=$(make_fixture_bundle MyApp com.example.MyApp)
    # SIG_IGN survives the fork, so this sleep really does ignore SIGTERM.
    pid=$(spawn_detached 'trap "" TERM; sleep 5')
    stub_process_table "  ${pid} ${executable}" "  4242 ${executable}"
    stub_open

    capture "${RUN_APP_SH}" --root "${root}" --quit-timeout 1
    assert_exit 1
    assert_stderr_contains "ERR_RUN_QUIT_TIMEOUT"
    assert_stderr_contains "still running: ${pid}"
    assert_pid_alive "${pid}"
    assert_open_not_called
    head -n 1 "${CASE_DIR}/stderr" | grep -q '^ERR_RUN_QUIT_TIMEOUT: ' ||
        _fail "the first stderr line is not the failure code"
    kill -9 "${pid}" 2>/dev/null || true
}

case_missing_build() {
    root=$(make_fixture_root --no-app)
    stub_process_table "  1 /sbin/launchd" "  1 /sbin/launchd"
    stub_open

    capture "${RUN_APP_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_RUN_APP_MISSING"
    assert_stderr_contains "just build"
    assert_open_not_called
}

case_launch_failure() {
    root=$(make_fixture_root)
    stub_process_table "  1 /sbin/launchd" "  1 /sbin/launchd"
    stub_open 1

    capture "${RUN_APP_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_RUN_LAUNCH_FAILED"
}

case_manifest_failure_is_the_helpers() {
    # No project.yml: the bundle-id helper owns that failure, and run-app.sh
    # passes it through rather than inventing a second code for it.
    root=$(make_temp_dir)
    mkdir -p "${root}/${APP_RELATIVE_PATH}"
    capture "${RUN_APP_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_BUNDLEID_MANIFEST_MISSING"
}

case_unknown_argument() {
    capture "${RUN_APP_SH}" --nope
    assert_exit 1
    assert_stderr_contains "ERR_RUN_USAGE"
}

case_bad_quit_timeout() {
    root=$(make_fixture_root)
    capture "${RUN_APP_SH}" --root "${root}" --quit-timeout soon
    assert_exit 1
    assert_stderr_contains "ERR_RUN_USAGE"
}

case_zero_quit_timeout() {
    root=$(make_fixture_root)
    for zero in 0 00; do
        capture "${RUN_APP_SH}" --root "${root}" --quit-timeout "${zero}"
        assert_exit 1
        assert_stderr_contains "ERR_RUN_USAGE"
    done
}

case_leading_zero_quit_timeout() {
    # A leading zero must not reach the arithmetic that sizes the poll: '010'
    # would read as octal there, and '08' would abort bash itself — after the
    # SIGTERM had already gone out, with no ERR_RUN_* line to act on.
    root=$(make_fixture_root)
    executable=$(make_fixture_bundle MyApp com.example.MyApp)
    pid=$(spawn_detached 'sleep 30')
    stub_process_table "  ${pid} ${executable}" "  4242 ${executable}"
    stub_open

    capture "${RUN_APP_SH}" --root "${root}" --quit-timeout 08
    assert_exit 0
    assert_pid_gone "${pid}"
    assert_stderr_not_contains "value too great for base" "bash's own arithmetic error"
    assert_open_called_with "${root}/${APP_RELATIVE_PATH}"
}

run_case "quits the running instance, then launches the fresh build" case_quits_then_launches
run_case "launches when no instance is running" case_launches_when_nothing_is_running
run_case "leaves a same-named app with another identifier alone" case_leaves_a_same_named_app_alone
run_case "reports a process that outlived the quit timeout" case_survivor_is_reported_not_forced
run_case "names a missing Debug build" case_missing_build
run_case "names a failed launch" case_launch_failure
run_case "passes the manifest failure through" case_manifest_failure_is_the_helpers
run_case "rejects an unknown argument" case_unknown_argument
run_case "rejects a non-numeric --quit-timeout" case_bad_quit_timeout
run_case "rejects a zero --quit-timeout, however spelled" case_zero_quit_timeout
run_case "reads a leading-zero --quit-timeout as base 10" case_leading_zero_quit_timeout
finish
