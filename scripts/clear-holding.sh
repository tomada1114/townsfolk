#!/usr/bin/env bash
# Delete what a shipping-issues run moved aside into its holding area — and nothing
# else. What `just clear-holding <name>...` runs.
#
#   scripts/clear-holding.sh [--state-dir DIR] <name>...
#
# The shipping-issues skill never deletes mid-run: it moves a probe, a scratch
# fixture, or a result bundle into <runstate>/holding/<name>/, where <name> is the
# issue number it was working (or `run`), and offers one deletion at the end. This
# script is that deletion, narrowed so it can be allowed without a prompt:
#
# - <name> is a bare issue number or the literal `run` — never a path, so no
#   argument can reach outside holding/ (no `..`, no `/`, no glob);
# - <runstate> is derived, never passed in: ${AGENT_SKILL_STATE_DIR:-$HOME/.local/
#   state/agent-skills}/shipping-issues/<owner>__<repo>/, with <owner>/<repo> read
#   from this checkout's `origin` remote, the same layout the skill writes;
# - holding/ itself is never removed, and a name with nothing held is a notice,
#   not an error, so clearing twice is harmless.
#
# `--state-dir DIR` replaces the derived <runstate> (the directory that holds
# holding/); it exists for the tests, and `just clear-holding` never passes it.
#
# Git work tree: required unless --state-dir is given — <owner>/<repo> comes from
# `git remote get-url origin`.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_HOLDING_USAGE      no name, a name that is not a number or `run`, or a bad --state-dir
#   ERR_HOLDING_NO_ORIGIN  not in a git work tree, or `origin` is not a GitHub URL
# Every name is checked before anything is deleted, so one bad name deletes nothing.
set -euo pipefail

USAGE="usage: scripts/clear-holding.sh <issue-number|run>..."

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

STATE_DIR=""
NAMES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --state-dir)
            [ $# -ge 2 ] || fail ERR_HOLDING_USAGE "--state-dir needs a directory" \
                "--state-dir followed by an existing directory" "no value after --state-dir" "${USAGE}"
            [ -d "$2" ] || fail ERR_HOLDING_USAGE "--state-dir directory '$2' does not exist" \
                "--state-dir followed by an existing directory" "no directory at '$2'" "${USAGE}"
            STATE_DIR=$(cd "$2" && pwd)
            shift
            ;;
        *)
            NAMES+=("$1")
            ;;
    esac
    shift
done

[ "${#NAMES[@]}" -gt 0 ] || fail ERR_HOLDING_USAGE "no holding name given" \
    "one or more issue numbers, or \`run\`" "no arguments" "${USAGE}"

for name in "${NAMES[@]}"; do
    case "${name}" in
        run) ;;
        '' | *[!0-9]*)
            fail ERR_HOLDING_USAGE "'${name}' is not an issue number or \`run\`" \
                "a bare issue number (e.g. 42) or \`run\`" "argument '${name}'; nothing was deleted" \
                "${USAGE}"
            ;;
    esac
done

if [ -z "${STATE_DIR}" ]; then
    origin=$(git remote get-url origin 2>/dev/null) || fail ERR_HOLDING_NO_ORIGIN \
        "cannot read this checkout's \`origin\` remote" \
        "a git work tree whose \`origin\` is a GitHub repository" \
        "\`git remote get-url origin\` failed" \
        "run this from the repository checkout (\`just clear-holding <name>\`)"
    slug=$(printf '%s\n' "${origin}" | sed -E -n 's#^.*github\.com[:/]([^/]+)/([^/]+)$#\1__\2#p')
    slug=${slug%.git}
    [ -n "${slug}" ] || fail ERR_HOLDING_NO_ORIGIN "\`origin\` is not a GitHub URL" \
        "an origin like git@github.com:<owner>/<repo>.git" "origin is '${origin}'" \
        "check \`git remote -v\`; shipping-issues names its state directory <owner>__<repo>"
    STATE_DIR="${AGENT_SKILL_STATE_DIR:-${HOME}/.local/state/agent-skills}/shipping-issues/${slug}"
fi

HOLDING="${STATE_DIR}/holding"
for name in "${NAMES[@]}"; do
    target="${HOLDING}/${name}"
    if [ ! -e "${target}" ] && [ ! -L "${target}" ]; then
        echo "clear-holding: nothing held for '${name}'"
        continue
    fi
    rm -rf "${target}"
    echo "clear-holding: removed ${target}"
done
