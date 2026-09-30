#!/usr/bin/env bash
# Prepare a release in one checked step: set MARKETING_VERSION in project.yml,
# increment CURRENT_PROJECT_VERSION, and roll CHANGELOG.md's [Unreleased] entries
# into a dated section, leaving a fresh empty [Unreleased].
#
#   scripts/release-prep.sh [--root DIR] [--dry-run] <version>
#
# These are the edits a release needs before its tag exists, and the reason to do
# them here is the order they are checked in: .github/workflows/release.yml refuses
# a tag whose name does not match MARKETING_VERSION, and it can only say so after
# the tag has been pushed. This script checks the same agreement beforehand, and
# prints the tag to push once the pull request is merged.
#
# What it writes: project.yml and CHANGELOG.md, and nothing else. It creates no
# commit, no tag, and no push — those stay human actions (AGENTS.md's "Security and
# human approval"), so the whole result is a reviewable two-file diff.
#
# <version> is MAJOR.MINOR.PATCH, each component a run of digits with no leading
# zero, and must be greater than the manifest's current MARKETING_VERSION compared
# component by component as a number (so 1.10.0 > 1.9.0). A pre-release or build
# suffix (1.0.0-rc.1, 1.0.0+42) is refused: semver's ordering rules for those are
# not what this comparison implements, and nothing downstream needs them — the
# release workflow only ever string-compares the tag against the manifest value.
#
# CHANGELOG.md is treated as Keep a Changelog: exactly one `## [Unreleased]`
# heading, its entries between that heading and the next `##` one. The heading
# stays where it is and the dated heading is inserted under it, so the entries move
# without being reordered or reformatted. When the file defines an `[Unreleased]:`
# link reference of the usual GitHub shape, a matching `[<version>]:` release-tag
# reference is added next to it — and for the `…/compare/<range>` shape, where the
# range names a version, the `[Unreleased]:` line itself is pointed at
# `compare/v<version>...HEAD`. A `…/commits/<branch>` line names no version, so it
# already points where it should and is left as it is. An `[Unreleased]:` line of
# any other shape is left alone too, and gets no companion reference: a wrong URL
# is worse than a heading that renders as plain text.
#
# The checks run in this order, and the tree state is checked last on purpose: a
# refusal about the version or the changelog is true whatever the tree looks like,
# so a second run for a version that is already released reports that, instead of
# reporting the uncommitted changes the first run made. --dry-run runs every check,
# including the clean-tree one, and writes nothing; a dry run that passes is a real
# run that passes.
#
# Git work tree: required — the clean-tree check is the point, and outside a work
# tree there is nothing to check it against (ERR_RELEASE_NOT_A_REPO).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_RELEASE_USAGE                 unknown argument, no version or more than one, or a --root DIR that does not exist
#   ERR_RELEASE_NOT_A_REPO            --root is not inside a git work tree
#   ERR_RELEASE_INPUT_MISSING         there is no project.yml or CHANGELOG.md under the root
#   ERR_RELEASE_VERSION_INVALID       <version> is not MAJOR.MINOR.PATCH
#   ERR_RELEASE_MANIFEST_VERSION      project.yml declares no MARKETING_VERSION, or not a MAJOR.MINOR.PATCH one
#   ERR_RELEASE_MANIFEST_BUILD        project.yml declares no CURRENT_PROJECT_VERSION, or not an integer
#   ERR_RELEASE_NOT_GREATER           <version> is not greater than the current MARKETING_VERSION
#   ERR_RELEASE_CHANGELOG_SHAPE       CHANGELOG.md has no single `## [Unreleased]` heading
#   ERR_RELEASE_CHANGELOG_DUPLICATE   CHANGELOG.md already has a section for <version>
#   ERR_RELEASE_CHANGELOG_EMPTY       the [Unreleased] section has no entries to release
#   ERR_RELEASE_GIT_FAILED            the work tree state could not be read
#   ERR_RELEASE_DIRTY_TREE            the work tree has uncommitted changes
#   ERR_RELEASE_WRITE_FAILED          a new file could not be built or moved into place
set -euo pipefail

USAGE="usage: scripts/release-prep.sh [--root DIR] [--dry-run] <version>"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

ROOT=""
DRY_RUN=0
VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || fail ERR_RELEASE_USAGE "--root needs a directory" \
                "--root followed by an existing directory" "no value after --root" "${USAGE}"
            [ -d "$2" ] || fail ERR_RELEASE_USAGE "--root directory '$2' does not exist" \
                "--root followed by an existing directory" "no directory at '$2'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        -*)
            fail ERR_RELEASE_USAGE "unknown argument '$1'" \
                "--root DIR, --dry-run, or a version" "argument '$1'" "${USAGE}"
            ;;
        *)
            [ -z "${VERSION}" ] || fail ERR_RELEASE_USAGE "more than one version was given" \
                "exactly one version argument" "'${VERSION}' and '$1'" "${USAGE}"
            VERSION="$1"
            ;;
    esac
    shift
done
[ -n "${VERSION}" ] || fail ERR_RELEASE_USAGE "no version was given" \
    "exactly one version argument, e.g. 0.2.0" "no version argument" "${USAGE}"
[ -n "${ROOT}" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [ "$(git -C "${ROOT}" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]; then
    fail ERR_RELEASE_NOT_A_REPO "${ROOT} is not inside a git work tree" \
        "a git checkout, whose work tree must be clean before a release is prepared" \
        "\`git -C ${ROOT} rev-parse --is-inside-work-tree\` did not print true" \
        "run this from a git checkout of this repository, or pass --root DIR"
fi

MANIFEST="${ROOT}/project.yml"
CHANGELOG="${ROOT}/CHANGELOG.md"
for required in "${MANIFEST}" "${CHANGELOG}"; do
    [ -f "${required}" ] || fail ERR_RELEASE_INPUT_MISSING "there is no ${required}" \
        "both ${MANIFEST} and ${CHANGELOG} to exist" "no file at ${required}" \
        "run this from a checkout of this repository, or pass --root DIR"
done

# A release version, and the one component of it this script may compare as a
# number: digits with no leading zero, three of them, nothing else.
is_release_version() {
    printf '%s' "$1" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
}

is_build_number() {
    printf '%s' "$1" | grep -Eq '^(0|[1-9][0-9]*)$'
}

if ! is_release_version "${VERSION}"; then
    fail ERR_RELEASE_VERSION_INVALID "'${VERSION}' is not a release version" \
        "MAJOR.MINOR.PATCH, each a run of digits with no leading zero and no pre-release or build suffix (e.g. 0.2.0)" \
        "'${VERSION}'" \
        "re-run with a plain MAJOR.MINOR.PATCH version"
fi

# The value of the first `<key>:` line in the manifest, quotes, a trailing YAML
# comment, and trailing whitespace removed — scripts/bundle-id.sh reads
# PRODUCT_BUNDLE_IDENTIFIER the same way, and the same rules apply here.
read_setting() { # read_setting <key>
    local value
    value=$(sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" "${MANIFEST}" | head -n 1)
    value=$(printf '%s' "${value}" | tr -d '\r' | sed -e 's/[[:space:]]#.*//' -e 's/[[:space:]]*$//')
    case "${value}" in
        \#*) value="" ;;
    esac
    case "${value}" in
        \"*\")
            value=${value#\"}
            value=${value%\"}
            ;;
        \'*\')
            value=${value#\'}
            value=${value%\'}
            ;;
    esac
    printf '%s' "${value}"
}

# "no such line" and "a line with a value this cannot use" are different manifest
# bugs, and the Actual: line says which one it is.
found_or_value() { # found_or_value <key> <value>
    if [ -n "$2" ]; then
        echo "$1 is '$2'"
    else
        echo "no such line, or an empty value"
    fi
}

CURRENT_VERSION=$(read_setting MARKETING_VERSION)
if ! is_release_version "${CURRENT_VERSION}"; then
    fail ERR_RELEASE_MANIFEST_VERSION "project.yml does not declare a usable MARKETING_VERSION" \
        "a \`MARKETING_VERSION: <MAJOR.MINOR.PATCH>\` line in ${MANIFEST}" \
        "$(found_or_value MARKETING_VERSION "${CURRENT_VERSION}")" \
        "fix the value in ${MANIFEST} (e.g. 0.1.0), then re-run"
fi

CURRENT_BUILD=$(read_setting CURRENT_PROJECT_VERSION)
if ! is_build_number "${CURRENT_BUILD}"; then
    fail ERR_RELEASE_MANIFEST_BUILD "project.yml does not declare a usable CURRENT_PROJECT_VERSION" \
        "a \`CURRENT_PROJECT_VERSION: <integer>\` line in ${MANIFEST}" \
        "$(found_or_value CURRENT_PROJECT_VERSION "${CURRENT_BUILD}")" \
        "fix the value in ${MANIFEST} (e.g. 1), then re-run"
fi
NEXT_BUILD=$((CURRENT_BUILD + 1))

# Component by component as numbers, so 1.10.0 > 1.9.0 — which a string compare,
# and so the reader of a sorted tag list, gets wrong.
version_is_greater() { # version_is_greater <a> <b>  -- true when a > b
    local a="$1" b="$2" i a_part b_part
    for i in 1 2 3; do
        a_part=$(printf '%s' "${a}" | cut -d. -f"${i}")
        b_part=$(printf '%s' "${b}" | cut -d. -f"${i}")
        if [ "${a_part}" -gt "${b_part}" ]; then
            return 0
        fi
        if [ "${a_part}" -lt "${b_part}" ]; then
            return 1
        fi
    done
    return 1
}

if ! version_is_greater "${VERSION}" "${CURRENT_VERSION}"; then
    NOT_GREATER_WHY="below it"
    if [ "${VERSION}" = "${CURRENT_VERSION}" ]; then
        NOT_GREATER_WHY="already the current version"
    fi
    fail ERR_RELEASE_NOT_GREATER "${VERSION} is not greater than the current version ${CURRENT_VERSION}" \
        "a version above MARKETING_VERSION ${CURRENT_VERSION}, compared component by component" \
        "${VERSION}, which is ${NOT_GREATER_WHY}" \
        "pick a higher version, or check whether ${VERSION} was already prepared (\`git log -1 project.yml\`)"
fi

UNRELEASED_HEADINGS=$(grep -c '^##[[:space:]]*\[Unreleased\][[:space:]]*$' "${CHANGELOG}" || true)
if [ "${UNRELEASED_HEADINGS}" != "1" ]; then
    fail ERR_RELEASE_CHANGELOG_SHAPE "CHANGELOG.md has no single \`## [Unreleased]\` heading" \
        "exactly one \`## [Unreleased]\` line in ${CHANGELOG} (Keep a Changelog)" \
        "${UNRELEASED_HEADINGS} such line(s)" \
        "restore the heading in ${CHANGELOG}, then re-run"
fi

VERSION_RE=$(printf '%s' "${VERSION}" | sed 's/\./\\./g')
if grep -Eq "^##[[:space:]]*\[${VERSION_RE}\]" "${CHANGELOG}"; then
    fail ERR_RELEASE_CHANGELOG_DUPLICATE "CHANGELOG.md already has a section for ${VERSION}" \
        "no \`## [${VERSION}]\` heading in ${CHANGELOG} yet" \
        "a \`## [${VERSION}]\` heading is already there" \
        "pick a higher version, or remove the stale section from ${CHANGELOG}"
fi

# The entries between `## [Unreleased]` and the next `##` heading. A `### Added`
# subheading, a blank line, and a link reference definition are structure rather
# than an entry, so a section holding only those is empty.
ENTRY_COUNT=$(awk '
    /^##[ \t]*\[Unreleased\][ \t]*$/ { inside = 1; next }
    inside && /^##[ \t]/ { inside = 0 }
    inside {
        if ($0 ~ /^[ \t]*$/) next
        if ($0 ~ /^###/) next
        if ($0 ~ /^\[[^]]+\]:[ \t]/) next
        n++
    }
    END { print n + 0 }
' "${CHANGELOG}")
if [ "${ENTRY_COUNT}" = "0" ]; then
    fail ERR_RELEASE_CHANGELOG_EMPTY "the [Unreleased] section of CHANGELOG.md has no entries" \
        "at least one entry under \`## [Unreleased]\` in ${CHANGELOG} to release" \
        "the section holds no entry line" \
        "add the user-facing changes to ${CHANGELOG} (CONTRIBUTING.md's Changelog Policy), then re-run"
fi

# Only git's stdout is the list of pending changes. Its stderr is not: a
# configured-but-broken hook (core.fsmonitor, say) makes git print a `fatal:` line
# and still exit 0 with an empty, correct listing, and folding that line into the
# list would refuse a clean tree as dirty. So stderr is read only when git actually
# fails, by asking it again on that path alone.
if ! DIRTY=$(git -C "${ROOT}" status --porcelain 2>/dev/null); then
    GIT_MESSAGE=$(git -C "${ROOT}" status --porcelain 2>&1 >/dev/null | head -n 1 || true)
    [ -n "${GIT_MESSAGE}" ] || GIT_MESSAGE="\`git status --porcelain\` failed without a message"
    fail ERR_RELEASE_GIT_FAILED "the work tree state could not be read" \
        "\`git -C ${ROOT} status --porcelain\` to list the pending changes" \
        "${GIT_MESSAGE}" \
        "run \`git -C ${ROOT} status\` and fix what it reports"
fi
if [ -n "${DIRTY}" ]; then
    DIRTY_COUNT=$(printf '%s\n' "${DIRTY}" | wc -l | tr -d ' ')
    DIRTY_HEAD=$(printf '%s\n' "${DIRTY}" | head -n 3 | cut -c4- | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    [ "${DIRTY_COUNT}" -le 3 ] || DIRTY_HEAD="${DIRTY_HEAD} (and more)"
    fail ERR_RELEASE_DIRTY_TREE "the work tree has uncommitted changes" \
        "a clean work tree, so the release edits are the whole of the next diff" \
        "${DIRTY_COUNT} uncommitted change(s): ${DIRTY_HEAD}" \
        "commit or stash them (\`git -C ${ROOT} status\`), then re-run"
fi

DATE=$(date +%Y-%m-%d)
HEADING="## [${VERSION}] - ${DATE}"

# The link reference the new heading needs, when the file defines an [Unreleased]
# one of a shape this can extend (…/commits/<branch> or …/compare/<range>, both of
# which GitHub writes). Anything else is left untouched: a wrong URL is worse than
# a heading that renders as plain text.
#
# The `[Unreleased]:` line is matched twice — here, to read its URL, and by the awk
# below, to write beside or over it — and the two must agree, or this prints a plan
# the write does not carry out. `^\[Unreleased\]:[[:space:]]*` is therefore spelled
# identically in both, which it can be: `\[` is a literal bracket and
# `[[:space:]]` a POSIX class to sed's regular expressions and to awk's alike, on
# both platforms these scripts run on (a `[ \t]` class would not be: BSD sed reads
# that `\t` as a backslash and a `t`, not a tab). The whitespace
# is optional because a Markdown link reference definition allows none.
UNRELEASED_URL=$(sed -n 's/^\[Unreleased\]:[[:space:]]*//p' "${CHANGELOG}" | head -n 1 | tr -d '\r' | sed 's/[[:space:]]*$//')
LINK_REFERENCE=""
# For the compare shape the new [Unreleased]: range is not a guess — it is the tag
# this run prepares, compared against HEAD, which is what Keep a Changelog asks for
# and what the old range said about the previous release. The commits shape names no
# version, so it already points where it should and is left as it is.
UNRELEASED_REPLACEMENT=""
case "${UNRELEASED_URL}" in
    *://*/commits/*)
        LINK_REFERENCE="[${VERSION}]: ${UNRELEASED_URL%/commits/*}/releases/tag/v${VERSION}"
        ;;
    *://*/compare/*)
        LINK_REFERENCE="[${VERSION}]: ${UNRELEASED_URL%/compare/*}/releases/tag/v${VERSION}"
        UNRELEASED_REPLACEMENT="[Unreleased]: ${UNRELEASED_URL%/compare/*}/compare/v${VERSION}...HEAD"
        ;;
esac

# Both new files are built beside their targets and only then moved into place, so a
# failure half way through leaves the checkout as it was. They are written next to
# the originals rather than under TMPDIR because `mv` across filesystems is a copy,
# which is not atomic.
TMP_MANIFEST="${MANIFEST}.release-prep.$$"
TMP_CHANGELOG="${CHANGELOG}.release-prep.$$"
trap 'rm -f "${TMP_MANIFEST}" "${TMP_MANIFEST}.build" "${TMP_CHANGELOG}"' EXIT

# Rewrites the first `<key>:` line, keeping its indentation, its quoting style, and
# any trailing comment: this edit is read as a diff, so it changes the value alone.
set_setting() { # set_setting <input> <output> <key> <value>
    awk -v key="$3" -v value="$4" '
        !replaced && match($0, "^[ \t]*" key ":[ \t]*") {
            head = substr($0, 1, RLENGTH)
            tail = substr($0, RLENGTH + 1)
            quote = ""
            if (substr(tail, 1, 1) == "\"") quote = "\""
            else if (substr(tail, 1, 1) == "'\''") quote = "'\''"
            if (quote != "") {
                end = index(substr(tail, 2), quote)
                rest = (end > 0) ? substr(tail, end + 2) : ""
            } else {
                rest = match(tail, /[ \t]/) ? substr(tail, RSTART) : ""
            }
            print head quote value quote rest
            replaced = 1
            next
        }
        { print }
    ' "$1" >"$2"
}

if ! set_setting "${MANIFEST}" "${TMP_MANIFEST}" MARKETING_VERSION "${VERSION}"; then
    fail ERR_RELEASE_WRITE_FAILED "the new project.yml could not be built" \
        "MARKETING_VERSION rewritten to ${VERSION} in a temporary copy" \
        "the rewrite of ${MANIFEST} failed" \
        "check that ${ROOT} is writable, then re-run"
fi
if ! set_setting "${TMP_MANIFEST}" "${TMP_MANIFEST}.build" CURRENT_PROJECT_VERSION "${NEXT_BUILD}" ||
    ! mv "${TMP_MANIFEST}.build" "${TMP_MANIFEST}"; then
    fail ERR_RELEASE_WRITE_FAILED "the new project.yml could not be built" \
        "CURRENT_PROJECT_VERSION rewritten to ${NEXT_BUILD} in a temporary copy" \
        "the rewrite of ${MANIFEST} failed" \
        "check that ${ROOT} is writable, then re-run"
fi

# The [Unreleased] heading stays; the dated heading goes under it, with exactly one
# blank line on each side however the original was spaced, and the entries follow
# it unchanged.
if ! awk -v heading="${HEADING}" -v linkref="${LINK_REFERENCE}" \
    -v unreleased_line="${UNRELEASED_REPLACEMENT}" '
    !inserted && /^##[ \t]*\[Unreleased\][ \t]*$/ {
        print $0
        print ""
        print heading
        print ""
        inserted = 1
        skipping_blanks = 1
        next
    }
    skipping_blanks && /^[ \t]*$/ { next }
    { skipping_blanks = 0 }
    # The same expression the URL was read with, spelled identically.
    !linked && linkref != "" && /^\[Unreleased\]:[[:space:]]*/ {
        print (unreleased_line != "" ? unreleased_line : $0)
        print linkref
        linked = 1
        next
    }
    { print }
' "${CHANGELOG}" >"${TMP_CHANGELOG}"; then
    fail ERR_RELEASE_WRITE_FAILED "the new CHANGELOG.md could not be built" \
        "the [Unreleased] entries moved under \"${HEADING}\" in a temporary copy" \
        "the rewrite of ${CHANGELOG} failed" \
        "check that ${ROOT} is writable, then re-run"
fi

echo "release-prep: plan for ${VERSION}"
echo "  project.yml: MARKETING_VERSION ${CURRENT_VERSION} -> ${VERSION}"
echo "  project.yml: CURRENT_PROJECT_VERSION ${CURRENT_BUILD} -> ${NEXT_BUILD}"
echo "  CHANGELOG.md: the [Unreleased] entries -> \"${HEADING}\", leaving [Unreleased] empty"
if [ -n "${LINK_REFERENCE}" ]; then
    echo "  CHANGELOG.md: link reference ${LINK_REFERENCE}"
fi
if [ -n "${UNRELEASED_REPLACEMENT}" ]; then
    echo "  CHANGELOG.md: link reference ${UNRELEASED_REPLACEMENT}"
fi

if [ "${DRY_RUN}" = 1 ]; then
    echo "release-prep: --dry-run, nothing was written. Re-run without --dry-run to apply."
    exit 0
fi

if ! mv "${TMP_MANIFEST}" "${MANIFEST}" || ! mv "${TMP_CHANGELOG}" "${CHANGELOG}"; then
    fail ERR_RELEASE_WRITE_FAILED "a prepared file could not be moved into place" \
        "the prepared project.yml and CHANGELOG.md to replace the originals" \
        "\`mv\` failed in ${ROOT}" \
        "run \`git -C ${ROOT} status\` to see what changed, and \`git -C ${ROOT} checkout -- project.yml CHANGELOG.md\` to undo it"
fi

cat <<EOF
release-prep: wrote project.yml and CHANGELOG.md. No commit, tag, or push was created.

Next, by hand:

  1. git diff                                  # review the two edits
  2. git switch -c release/${VERSION}                # if you are still on main
  3. git add project.yml CHANGELOG.md
  4. git commit -m 'chore(release): ${VERSION}'
  5. git push -u origin release/${VERSION}
  6. gh pr create --fill

Then, once that pull request is merged into main, tag the merge commit — pushing the
tag is what starts .github/workflows/release.yml, and it refuses a tag that does not
match MARKETING_VERSION:

  7. git switch main && git pull
  8. git tag v${VERSION}
  9. git push origin v${VERSION}
EOF
