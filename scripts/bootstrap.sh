#!/usr/bin/env bash
# bootstrap:keep-begin
# Template bootstrap: rename every placeholder to your app's identity.
#
#   scripts/bootstrap.sh NewName [--bundle-id-prefix ID] [--github-user USER]
#                                [--author "Full Name"] [--email ADDRESS] [--repo slug]
#
# Replaces (in all git-tracked text files):
#   MyApp        -> NewName            (also MyAppKit/MyAppCore/MyAppUI/
#                                      MyAppPlatform/MyAppTestSupport/MyAppApp)
#   my-app       -> repo slug          (default: kebab-case of NewName)
#   com.example  -> --bundle-id-prefix (kept if omitted)
#   your-username / Your Name / you@example.com -> optional args (kept if omitted)
#
# Then renames MyApp* paths and regenerates the Xcode project.
# Also removes the template-only CI job (bootstrap-smoke) and its required check
# in .github/rulesets/main.json.
# Records the template commit and repository in .template-origin (first run only;
# never rewritten by the rename, and "unknown" when this checkout's history does not
# start at the template's root commit — see the comment above the ORIGIN_FILE block).
# Running it again with the same name is a no-op, so it is safe to re-run
# (values a previous run already replaced are not replaced again).
#
# Passages that explain the placeholders (this header, README's "Using This
# Template", the starting-an-app skill) sit between a keep-begin and a keep-end
# marker line (KEEP_BEGIN and KEEP_END below spell them) and are never
# rewritten, so they still read correctly after the rename.
# bootstrap:keep-end
set -euo pipefail

# The placeholder literals are quote-split so replace() below never rewrites
# this script's own match sources — a re-run keeps matching the original
# placeholders instead of whatever a previous run substituted for them.
PH_NAME='My''App'
PH_SLUG='my''-app'
PH_BUNDLE='com''.example'
PH_USER='your''-username'
PH_AUTHOR='Your'' Name'
PH_EMAIL='you''@example.com'
# The keep markers, split for the same reason: replace() would otherwise treat
# the lines below that name them as markers.
KEEP_BEGIN='bootstrap:keep''-begin'
KEEP_END='bootstrap:keep''-end'

usage() {
    # Print the header comment: lines after the shebang up to the first non-comment.
    awk 'NR > 1 && !/^#/ { exit } /bootstrap:keep-/ { next } NR > 1 { sub(/^# ?/, ""); print }' "$0"
    exit 1
}

[ $# -ge 1 ] || usage
NEW_NAME="$1"
shift

if ! [[ "${NEW_NAME}" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
    echo "error: '${NEW_NAME}' is not PascalCase (expected ^[A-Z][A-Za-z0-9]*$)" >&2
    exit 1
fi
if [[ "${NEW_NAME}" == *"${PH_NAME}"* ]]; then
    echo "error: '${NEW_NAME}' contains the placeholder '${PH_NAME}' — a re-run would corrupt the rename; pick a different name" >&2
    exit 1
fi

# Default slug: kebab-case of NewName (DemoApp -> demo-app, HTTPServer -> http-server).
DEFAULT_SLUG=$(echo "${NEW_NAME}" | perl -pe 's/([A-Z]+)([A-Z][a-z])/$1-$2/g; s/([a-z0-9])([A-Z])/$1-$2/g' | tr '[:upper:]' '[:lower:]')

BUNDLE_ID_PREFIX=""
GITHUB_USER=""
AUTHOR=""
EMAIL=""
REPO_SLUG="${DEFAULT_SLUG}"

while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-id-prefix) BUNDLE_ID_PREFIX="$2"; shift 2 ;;
        --github-user)      GITHUB_USER="$2";      shift 2 ;;
        --author)           AUTHOR="$2";           shift 2 ;;
        --email)            EMAIL="$2";            shift 2 ;;
        --repo)             REPO_SLUG="$2";        shift 2 ;;
        *) echo "error: unknown option '$1'" >&2; usage ;;
    esac
done

if [[ "${REPO_SLUG}" == *"${PH_SLUG}"* ]]; then
    echo "error: repo slug '${REPO_SLUG}' contains the placeholder '${PH_SLUG}' — pass a different --repo" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

# replace() enumerates git-tracked files, so a checkout without .git cannot be
# bootstrapped (e.g. a GitHub ZIP download, or a clone whose .git was removed).
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: bootstrap.sh needs a git checkout to enumerate files (git ls-files)." >&2
    echo "       If you removed .git, re-create it first: git init && git add -A" >&2
    exit 1
fi

ORIGIN_FILE=".template-origin"

replace() { # replace <from> <to> — literal replacement in all tracked text files,
    # except lines from a KEEP_BEGIN marker line through the next KEEP_END line
    local from="$1" to="$2" file
    [ "${from}" = "${to}" ] && return 0
    git ls-files -z | while IFS= read -r -d '' file; do
        [ -f "${file}" ] || continue
        # Never rewrite the recorded origin: a fork of this template can be owned
        # by, or named after, one of the placeholder literals above, and a
        # rewritten URL would point at a repository that does not exist.
        [ "${file}" != "${ORIGIN_FILE}" ] || continue
        grep -Iq . "${file}" 2>/dev/null || continue # skip binary and empty files
        grep -qF -- "${from}" "${file}" || continue  # leave non-matching files untouched
        FROM="${from}" TO="${to}" KB="${KEEP_BEGIN}" KE="${KEEP_END}" perl -pi -e '
            $keep = 1 if index($_, $ENV{KB}) >= 0;
            s/\Q$ENV{FROM}\E/$ENV{TO}/g unless $keep;
            $keep = 0 if index($_, $ENV{KE}) >= 0;
        ' "${file}"
    done
}

# Record which template commit this app was cut from, so "what has the template
# fixed since?" is one command instead of a two-history read. Decisions encoded here:
#   * Written only when the file is absent. A re-run, and any hand-edit made after
#     merging template changes, therefore survives untouched.
#   * replace() skips it (see above), so the rename cannot rewrite the URL.
#   * HEAD is recorded only when this history really is the template's: its root
#     commit is TEMPLATE_ROOT, the template's first commit, which every clone and fork
#     of the template shares and which no rename touches. GitHub's "Use this template"
#     gives the new repository a fresh root instead — there HEAD is a commit the
#     template has never seen (however many commits follow it) and "origin" is the new
#     app, not the template — so both values are "unknown". A SHA that
#     `git log <sha>..template/main` rejects as an unknown revision is worse than an
#     honest "unknown", so the file names the tree to search the template's history
#     for instead. A shallow clone cannot show its root, so it is "unknown" too.
TEMPLATE_ROOT="3a9750f6548c1c745267a73ed3e22318d9380745"
if [ -e "${ORIGIN_FILE}" ]; then
    echo "==> Keeping the existing ${ORIGIN_FILE}"
else
    ORIGIN_SHA="unknown"
    ORIGIN_URL="unknown"
    ORIGIN_TREE="$(git rev-parse 'HEAD^{tree}' 2>/dev/null || echo unknown)"
    if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" != "true" ] &&
        grep -qx "${TEMPLATE_ROOT}" <<<"$(git rev-list --max-parents=0 HEAD 2>/dev/null)"; then
        ORIGIN_SHA="$(git rev-parse HEAD)"
        ORIGIN_URL="$(git config --get remote.origin.url || echo unknown)"
    fi
    echo "==> Recording the template origin in ${ORIGIN_FILE} (${ORIGIN_SHA})"
    {
        echo "${ORIGIN_SHA}"
        echo "${ORIGIN_URL}"
        echo "# Written once by scripts/bootstrap.sh; a re-run leaves this file alone."
        echo "# Line 1: the template commit this app was created from. Line 2: its repository."
        if [ "${ORIGIN_SHA}" = "unknown" ]; then
            cat <<EOF
# Both are unknown: this checkout's history does not start at the template's root
# commit (or is a shallow clone), so its HEAD is not known to be a template commit and
# "origin" is this app rather than the template. That is what GitHub's "Use this
# template" produces. Find the template commit holding the same files, then fill both
# lines in by hand:
#   git log --format='%H %T' template/main | grep ${ORIGIN_TREE}
EOF
        fi
        echo "# See README.md, \"Keeping up with template updates\"."
    } >"${ORIGIN_FILE}"
fi

# Reset the template's own CHANGELOG history for the new project. Guarded by a
# marker so a re-run (documented as safe) never wipes the new app's entries.
if grep -qF 'Initial template: XcodeGen-generated app shell' CHANGELOG.md 2>/dev/null; then
    echo "==> Resetting CHANGELOG.md for the new project"
    cat > CHANGELOG.md <<EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial project scaffold from [macos-app-template](https://github.com/tomada1114/macos-app-template)

[Unreleased]: https://github.com/${PH_USER}/${PH_SLUG}/commits/main
EOF
fi

# Strip SECURITY.md's template-only passages: they address a repository created from
# the template, a reader an app repository does not have. Each sits between the
# marker lines below (split so replace() never sees one here), which go with it.
# Guarded by their presence, so a re-run is a no-op.
TPL_ONLY_BEGIN='bootstrap:template-only''-begin'
TPL_ONLY_END='bootstrap:template-only''-end'
if grep -qF "${TPL_ONLY_BEGIN}" SECURITY.md 2>/dev/null; then
    echo "==> Removing SECURITY.md's template-only passages"
    # The block, its marker lines, and the blank line before it.
    TB="${TPL_ONLY_BEGIN}" TE="${TPL_ONLY_END}" perl -0pi -e 's/\n?[^\n]*\Q$ENV{TB}\E.*?\Q$ENV{TE}\E[^\n]*\n//gs' SECURITY.md
fi

# Retire the template-only CI job. bootstrap-smoke renames a pristine copy of the
# template; once this rename has run there is nothing left for it to rename, so it
# can only fail. Remove the job and its required-check entry together. Guarded by
# their presence, so a re-run (or an app that already removed them) is a no-op.
CI_FILE=".github/workflows/ci.yml"
RULESET_FILE=".github/rulesets/main.json"
SMOKE_JOB='  bootstrap-smoke:'
SMOKE_NAME='Template Bootstrap Smoke'
if grep -qxF "${SMOKE_JOB}" "${CI_FILE}" 2>/dev/null || grep -qF "\"${SMOKE_NAME}\"" "${RULESET_FILE}" 2>/dev/null; then
    echo "==> Retiring the template-only bootstrap-smoke CI job"
    # The job key, then every following line that is blank or indented 4+ spaces,
    # i.e. up to (not including) the next 2-space-indented job key or EOF.
    [ -f "${CI_FILE}" ] && perl -0pi -e 's/^  bootstrap-smoke:\n(?:(?:    [^\n]*)?\n)*//m' "${CI_FILE}"
    # Only the one-line, comma-terminated shape is deleted, so the JSON stays valid;
    # any other shape is left alone and reported below.
    [ -f "${RULESET_FILE}" ] && perl -ni -e 'print unless /^\s*\{ "context": "Template Bootstrap Smoke", "integration_id": \d+ \},\s*$/' "${RULESET_FILE}"
    if grep -qxF "${SMOKE_JOB}" "${CI_FILE}" 2>/dev/null || grep -qF "${SMOKE_NAME}" "${CI_FILE}" "${RULESET_FILE}" 2>/dev/null; then
        echo "error: could not retire the template's bootstrap-smoke job automatically." >&2
        echo "       Still present (anything already removed was left removed):" >&2
        grep -nE "^${SMOKE_JOB}\$|${SMOKE_NAME}" "${CI_FILE}" "${RULESET_FILE}" 2>/dev/null | sed 's/^/         /' >&2 || true
        echo "       Remove those lines by hand (keep ${RULESET_FILE} valid JSON), then re-run this script." >&2
        exit 1
    fi
fi

echo "==> Replacing placeholders"
replace "${PH_NAME}" "${NEW_NAME}"
replace "${PH_SLUG}" "${REPO_SLUG}"
[ -n "${BUNDLE_ID_PREFIX}" ] && replace "${PH_BUNDLE}" "${BUNDLE_ID_PREFIX}"
[ -n "${GITHUB_USER}" ] && replace "${PH_USER}" "${GITHUB_USER}"
[ -n "${AUTHOR}" ] && replace "${PH_AUTHOR}" "${AUTHOR}"
[ -n "${EMAIL}" ] && replace "${PH_EMAIL}" "${EMAIL}"

echo "==> Renaming ${PH_NAME}* paths"
# Drop any stale generated project first; it is rebuilt below.
rm -rf "${PH_NAME}.xcodeproj" "${NEW_NAME}.xcodeproj"
# -depth renames the deepest entries first, so only basenames need rewriting.
# Skip VCS internals and build artifacts (SwiftPM's Packages/*/.build and the
# derived-data dir build/) — they are regenerable and full of matching paths.
find . -depth -name "*${PH_NAME}*" \
    -not -path "./.git/*" -not -path "*/.build/*" -not -path "./build/*" \
    | while IFS= read -r path; do
    base=$(basename "${path}")
    # Unquoted expansions: bash 3.2 (the runners' /bin/bash) treats quotes
    # inside ${var//pat/rep} literally. Both values are validated alphanumeric.
    target="$(dirname "${path}")/${base//${PH_NAME}/${NEW_NAME}}"
    if [ "${path}" != "${target}" ]; then
        mv "${path}" "${target}"
    fi
done

echo "==> Regenerating Xcode project"
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
elif command -v mise >/dev/null 2>&1; then
    mise exec -- xcodegen generate
else
    echo "warning: xcodegen not found — run 'just generate' after installing tools" >&2
fi

# A longer name moves line widths and import order, so the renamed tree must be
# re-formatted or the pre-commit hook refuses the bootstrap commit (issue #204).
echo "==> Formatting the renamed tree"
if command -v swiftformat >/dev/null 2>&1; then
    swiftformat --quiet .
elif command -v mise >/dev/null 2>&1; then
    mise exec -- swiftformat --quiet .
else
    echo "warning: swiftformat not found — run 'just fmt' after installing tools" >&2
fi

echo
echo "Bootstrap complete: ${PH_NAME} -> ${NEW_NAME} (repo slug: ${REPO_SLUG})"
[ -n "${BUNDLE_ID_PREFIX}" ] && echo "  bundle-id prefix: ${BUNDLE_ID_PREFIX}"
echo
echo "Next steps:"
echo "  1. Fill in AGENTS.md's '## Product' section (what the app is, who for, the"
echo "     core interaction, its non-goals) and delete every TODO: marker there —"
echo "     'just check' fails until you do"
echo "     Then fill in the docs/architecture/roadmap.md skeleton (steering-the-roadmap"
echo "     skill); nothing checks that page"
echo "  2. Verify the rename: just install && just check"
echo "  3. Create the label set on the new repository: just labels"
echo "  4. Review the changes: git diff"
echo "  5. Update README.md, SECURITY.md, the rest of AGENTS.md, and CODE_OF_CONDUCT.md"
echo "     for your app, and review LICENSE's copyright line (year and holder)"
echo "  6. Replace or remove the example code (the counter and the FrontmostApp"
echo "     port/adapter): docs/getting-started.md, 'Removing the example code'"
echo "  7. Check for leftovers: rg -i '${PH_NAME}|${PH_SLUG}|${PH_BUNDLE}|${PH_USER}'"
echo "     (the passages that explain the placeholders are kept on purpose)"
echo "  8. Commit: git add -A && git commit -m 'chore: bootstrap ${NEW_NAME} from template'"
echo "  9. Optional, repository admin only, after pushing that commit: just ruleset"
echo "     (applies the main branch ruleset, which then requires pull requests)"
