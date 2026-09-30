#!/usr/bin/env bash
# Forget every TCC permission decision macOS has recorded for this app, so the next
# launch asks again. What `just reset-permissions` runs.
#
#   scripts/reset-permissions.sh [--root DIR]
#
# `tccutil reset All <bundle id>` is destructive — it drops the user's own grants —
# so the identifier is never a free-form argument: it is read from project.yml
# (scripts/bundle-id.sh), the manifest that is the source of truth for the app
# target, which is also what makes this keep working after scripts/bootstrap.sh
# renames the app. The one way to aim it elsewhere is `--root DIR`, which follows
# the manifest under DIR — it exists for the tests, and `just reset-permissions`
# never passes it.
#
# When you need it: after switching a Debug build between ad-hoc signing and a real
# identity (Config/Debug.xcconfig), macOS sees a different app and System Settings
# is left showing a stale entry for the old one that no longer grants anything.
# Resetting clears both, and the next launch prompts from scratch. An app whose
# grants are still ad-hoc-keyed also needs this after most rebuilds — which is the
# loop Config/Local.xcconfig exists to end (docs/getting-started.md).
#
# `tccutil` ships with macOS and is not a mise tool, so — like `git` and `gh` — it
# is taken from PATH rather than routed through `mise exec --`.
#
# Git work tree: not required — the manifest is read under --root, which defaults to
# the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_RESET_USAGE         unknown argument, or a --root DIR that does not exist
#   ERR_RESET_TOOL_MISSING  `tccutil` is not on PATH (it ships with macOS only)
#   ERR_RESET_FAILED        `tccutil reset All` exited non-zero
# A failure to read the identifier prints scripts/bundle-id.sh's own ERR_BUNDLEID_*
# block instead, and nothing is reset.
set -euo pipefail

USAGE="usage: scripts/reset-permissions.sh [--root DIR]"

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
            [ $# -ge 2 ] || fail ERR_RESET_USAGE "--root needs a directory" \
                "--root followed by an existing directory" "no value after --root" "${USAGE}"
            [ -d "$2" ] || fail ERR_RESET_USAGE "--root directory '$2' does not exist" \
                "--root followed by an existing directory" "no directory at '$2'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *)
            fail ERR_RESET_USAGE "unknown argument '$1'" \
                "no arguments, or --root DIR" "argument '$1'" "${USAGE}"
            ;;
    esac
    shift
done
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
[ -n "${ROOT}" ] || ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

if ! command -v tccutil >/dev/null 2>&1; then
    fail ERR_RESET_TOOL_MISSING "'tccutil' is not on PATH" \
        "tccutil, which ships with macOS, on PATH" \
        "\`command -v tccutil\` found nothing" \
        "run this on macOS — there is no TCC database to reset anywhere else"
fi

# A failure here (no manifest, no identifier) prints its own ERR_BUNDLEID_* block.
BUNDLE_ID=$("${SCRIPT_DIR}/bundle-id.sh" --root "${ROOT}")

echo "==> Resetting all TCC permissions for ${BUNDLE_ID}"
if ! tccutil reset All "${BUNDLE_ID}"; then
    fail ERR_RESET_FAILED "\`tccutil reset All ${BUNDLE_ID}\` exited non-zero" \
        "tccutil to drop every recorded permission decision for ${BUNDLE_ID}" \
        "it failed; the grants are unchanged" \
        "run \`tccutil reset All ${BUNDLE_ID}\` and read its error, then quit the app and retry"
fi

echo "reset-permissions: ${BUNDLE_ID} will be asked for permission again on its next launch"
