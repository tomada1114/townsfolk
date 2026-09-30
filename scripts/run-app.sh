#!/usr/bin/env bash
# Relaunch the Debug build: quit every running instance of this app, wait for it
# to go, then launch the bundle `just build` just produced. What `just run` runs
# after its build step.
#
#   scripts/run-app.sh [--root DIR] [--quit-timeout SECONDS]
#
# A bare `open` on an app that is already running only activates the old
# process, so the freshly built binary never starts and the developer — or an
# agent verifying its own change — watches stale behavior with no signal that
# anything went wrong. Quitting first is what makes `just run` mean "run this
# build".
#
# An instance is identified by bundle identifier, never by process name: for
# each process whose executable sits inside an .app bundle, the bundle's
# CFBundleIdentifier is compared to the one project.yml declares
# (scripts/bundle-id.sh). A name match would also hit an unrelated app, or a
# same-named binary from another checkout, and would miss an instance launched
# from an older bundle whose executable was named differently.
#
# Each match is asked to quit with SIGTERM and the wait is bounded
# (--quit-timeout, 10 seconds by default). A survivor is reported, never
# SIGKILLed: an app that ignores SIGTERM is doing something, and the failure
# names the pid so the decision to force it stays with the caller.
#
# Git work tree: not required — the manifest and the build products are read
# under --root, which defaults to the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_RUN_USAGE          unknown argument, a --root DIR that does not exist,
#                          or a --quit-timeout that is not a positive integer
#   ERR_RUN_APP_MISSING    there is no built .app at the Debug products path
#   ERR_RUN_QUIT_TIMEOUT   a running instance did not exit within the bound
#   ERR_RUN_LAUNCH_FAILED  `open` refused to launch the bundle
set -euo pipefail

APP_NAME="MyApp"
APP_RELATIVE_PATH="build/dev-derived-data/Build/Products/Debug/${APP_NAME}.app"
QUIT_TIMEOUT=10
# The launch poll only decides what to print, so it stays short: `open` has
# already succeeded by then, and whether the app keeps running is the smoke
# test's question (scripts/smoke_launch.sh), not this script's.
LAUNCH_POLL_TRIES=10
POLL_INTERVAL=0.2
POLLS_PER_SECOND=5

USAGE="usage: scripts/run-app.sh [--root DIR] [--quit-timeout SECONDS]"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || fail ERR_RUN_USAGE "--root needs a directory" \
                "--root followed by an existing directory" "no value after --root" "${USAGE}"
            [ -d "$2" ] || fail ERR_RUN_USAGE "--root directory '$2' does not exist" \
                "--root followed by an existing directory" "no directory at '$2'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        --quit-timeout)
            [ $# -ge 2 ] || fail ERR_RUN_USAGE "--quit-timeout needs a value" \
                "--quit-timeout followed by a positive whole number of seconds" \
                "no value after --quit-timeout" "${USAGE}"
            case "$2" in
                "" | *[!0-9]*) fail ERR_RUN_USAGE "--quit-timeout '$2' is not a positive whole number" \
                    "--quit-timeout followed by a positive whole number of seconds" \
                    "'$2'" "${USAGE}" ;;
            esac
            # Forced to base 10 here, not at the arithmetic below: a leading zero
            # reads as octal there ('010' would mean 8 seconds, silently), and
            # '08' is not octal at all — bash would abort with a message of its
            # own, after the SIGTERM has gone out and before anything launched.
            # The same expansion turns '0' and '00' into the 0 rejected next.
            QUIT_TIMEOUT=$((10#$2))
            [ "${QUIT_TIMEOUT}" -gt 0 ] || fail ERR_RUN_USAGE "--quit-timeout '$2' is not a positive whole number" \
                "--quit-timeout followed by a positive whole number of seconds" \
                "'$2'" "${USAGE}"
            shift
            ;;
        *)
            fail ERR_RUN_USAGE "unknown argument '$1'" \
                "no arguments, --root DIR, or --quit-timeout SECONDS" "argument '$1'" "${USAGE}"
            ;;
    esac
    shift
done
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
[ -n "${ROOT}" ] || ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# A failure here (no manifest, no identifier) prints its own ERR_BUNDLEID_* block.
BUNDLE_ID=$("${SCRIPT_DIR}/bundle-id.sh" --root "${ROOT}")

APP_BUNDLE="${ROOT}/${APP_RELATIVE_PATH}"
[ -d "${APP_BUNDLE}" ] || fail ERR_RUN_APP_MISSING "there is no built app at ${APP_RELATIVE_PATH}" \
    "${APP_BUNDLE} to exist" "no app bundle at that path" \
    "run \`just build\` (\`just run\` builds first), then run this again"

# Prints the pid of every running process whose .app bundle declares BUNDLE_ID,
# one per line. `ps -o comm=` gives the executable's full path, so the bundle is
# the path up to the first `.app/Contents/MacOS/`; plutil then answers for that
# bundle. A path that is not inside an .app, or a bundle without a readable
# Info.plist, is not this app and is skipped.
matching_pids() {
    ps -A -o pid=,comm= | while read -r pid executable; do
        case "${executable}" in
            *.app/Contents/MacOS/*) ;;
            *) continue ;;
        esac
        # The shortest matching suffix, so a helper nested inside another app
        # bundle resolves to its own bundle rather than the outer one.
        bundle="${executable%.app/Contents/MacOS/*}.app"
        id=$(plutil -extract CFBundleIdentifier raw "${bundle}/Contents/Info.plist" 2>/dev/null || true)
        if [ "${id}" = "${BUNDLE_ID}" ]; then
            echo "${pid}"
        fi
    done
}

# one_line PIDS — the newline-separated pid list as one space-separated line.
one_line() {
    echo "$1" | tr '\n' ' ' | sed 's/ $//'
}

RUNNING=$(matching_pids)
if [ -n "${RUNNING}" ]; then
    echo "==> Quitting ${BUNDLE_ID} (pid $(one_line "${RUNNING}"))"
    for pid in ${RUNNING}; do
        kill -TERM "${pid}" 2>/dev/null || true
    done

    # Poll the known pids rather than re-reading the whole process table: the
    # table costs a plutil call per running app, and `kill -0` answers the only
    # question left — has this pid gone?
    tries=$((QUIT_TIMEOUT * POLLS_PER_SECOND))
    alive=""
    while [ "${tries}" -gt 0 ]; do
        alive=""
        for pid in ${RUNNING}; do
            if kill -0 "${pid}" 2>/dev/null; then
                alive="${alive} ${pid}"
            fi
        done
        [ -n "${alive}" ] || break
        sleep "${POLL_INTERVAL}"
        tries=$((tries - 1))
    done
    if [ -n "${alive}" ]; then
        alive="${alive# }"
        fail ERR_RUN_QUIT_TIMEOUT "a running instance of ${BUNDLE_ID} did not exit within ${QUIT_TIMEOUT}s" \
            "every process of ${BUNDLE_ID} to exit after SIGTERM" \
            "still running: ${alive}" \
            "quit the app by hand, or force it with \`kill -9 ${alive}\`, then run \`just run\` again"
    fi
fi

echo "==> Launching ${APP_RELATIVE_PATH}"
open "${APP_BUNDLE}" || fail ERR_RUN_LAUNCH_FAILED "\`open\` could not launch ${APP_BUNDLE}" \
    "\`open\` to launch the freshly built app" "\`open\` exited non-zero" \
    "run \`open ${APP_BUNDLE}\` and read its error; \`just build\` rebuilds the bundle"

tries="${LAUNCH_POLL_TRIES}"
LAUNCHED=""
while [ "${tries}" -gt 0 ]; do
    LAUNCHED=$(matching_pids)
    [ -z "${LAUNCHED}" ] || break
    sleep "${POLL_INTERVAL}"
    tries=$((tries - 1))
done
if [ -n "${LAUNCHED}" ]; then
    echo "run-app: ${BUNDLE_ID} is running (pid $(one_line "${LAUNCHED}"))"
else
    echo "run-app: launched ${BUNDLE_ID}, but no process of it is running yet — check \`just logs\`" >&2
fi
