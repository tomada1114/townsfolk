#!/usr/bin/env bash
# The "app actually runs" guarantee (uv-template smoke_test.py analog):
# build Release (or take a pre-built .app), verify the code signature, launch
# the binary, and assert the process stays alive. GUI assertions belong to the
# XCUITest, not here.
#
#   scripts/smoke_launch.sh                 # generate + build Release, then smoke-test
#   scripts/smoke_launch.sh path/to/An.app  # smoke-test an existing bundle (no build)
set -euo pipefail

APP_NAME="MyApp"
DERIVED_DATA="build/smoke-derived-data"
ALIVE_SECONDS=10

if [ $# -ge 1 ]; then
    # Strip a trailing slash (zsh tab completion appends it) and resolve to an
    # absolute path now, before the `cd` below re-roots relative paths at the repo.
    RAW_ARG="${1%/}"
    [ -d "${RAW_ARG}" ] || { echo "error: '${RAW_ARG}' is not an app bundle" >&2; exit 1; }
    APP_BUNDLE="$(cd "${RAW_ARG}" && pwd)"
fi

cd "$(dirname "$0")/.."

if [ -z "${APP_BUNDLE:-}" ]; then
    echo "==> Generating Xcode project"
    mise exec -- xcodegen generate

    echo "==> Building ${APP_NAME} (Release)"
    xcodebuild \
        -project "${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" \
        -configuration Release \
        -derivedDataPath "${DERIVED_DATA}" \
        build | mise exec -- xcbeautify --quiet

    APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
fi

APP_LABEL="$(basename "${APP_BUNDLE}" .app)"
BINARY_NAME="$(plutil -extract CFBundleExecutable raw "${APP_BUNDLE}/Contents/Info.plist")"
BINARY="${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"

echo "==> Verifying code signature"
codesign --verify --verbose=2 "${APP_BUNDLE}"

echo "==> Launching ${APP_LABEL} in the background"
"${BINARY}" &
APP_PID=$!
# Reap the app if the script itself is interrupted or fails mid-poll.
trap 'kill "${APP_PID}" 2>/dev/null || true' EXIT

# Poll: the process must stay alive for the whole window; an early crash fails.
for _ in $(seq 1 "${ALIVE_SECONDS}"); do
    sleep 1
    if ! kill -0 "${APP_PID}" 2>/dev/null; then
        STATUS=0
        wait "${APP_PID}" || STATUS=$?
        echo "SMOKE FAILED: ${APP_LABEL} exited early (status ${STATUS})" >&2
        exit 1
    fi
done

echo "==> Terminating ${APP_LABEL}"
kill "${APP_PID}"
# The app dies by our signal — that exit status is expected, not a failure.
wait "${APP_PID}" 2>/dev/null || true

echo "SMOKE OK: ${APP_LABEL} launched and stayed alive"
