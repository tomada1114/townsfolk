#!/usr/bin/env bash
# Tests for scripts/release-prep.sh: the two files it rewrites, the commands it
# prints, and the named refusal for each way a release can be prepared wrongly.
# Every case builds its own throwaway git repository with a fixture project.yml and
# CHANGELOG.md and points --root at it, so the real checkout is never read, never
# written, and never committed to. Nothing asserts on today's date: the dated
# heading is matched with a regex.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

RELEASE_PREP_SH="${REPO_ROOT}/scripts/release-prep.sh"

# write_manifest ROOT MARKETING_VERSION CURRENT_PROJECT_VERSION — shaped like the
# real project.yml: the settings are nested and quoted.
write_manifest() {
    cat >"$1/project.yml" <<EOF
name: MyApp
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "$2"
    CURRENT_PROJECT_VERSION: "$3"
targets:
  MyApp:
    type: application
EOF
}

# write_changelog ROOT — Keep a Changelog with one entry under [Unreleased] and the
# link reference this repository's CHANGELOG.md really carries.
write_changelog() {
    cat >"$1/CHANGELOG.md" <<'EOF'
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- A thing worth releasing

### Fixed

- A fixed thing

[Unreleased]: https://github.com/octo/my-app/commits/main
EOF
}

# Prints a fresh repository holding both fixtures, committed, so the work tree is clean.
make_fixture_repo() { # make_fixture_repo [MARKETING] [BUILD]
    local repo
    repo=$(make_temp_repo)
    write_manifest "${repo}" "${1:-0.1.0}" "${2:-1}"
    write_changelog "${repo}"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    echo "${repo}"
}

# The value of a project.yml setting, as the script's own reader would see it.
setting() { # setting FILE KEY
    sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -n 1 | tr -d '"'
}

case_rolls_the_release() {
    repo=$(make_fixture_repo)
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0

    [ "$(setting "${repo}/project.yml" MARKETING_VERSION)" = "0.2.0" ] ||
        _fail "MARKETING_VERSION was not set to 0.2.0"
    [ "$(setting "${repo}/project.yml" CURRENT_PROJECT_VERSION)" = "2" ] ||
        _fail "CURRENT_PROJECT_VERSION was not incremented to 2"
    grep -q 'SWIFT_VERSION: "6.0"' "${repo}/project.yml" ||
        _fail "an unrelated manifest setting was touched"

    # [Unreleased] keeps its place and stays empty: the very next non-blank line
    # after it is the dated heading, with one blank line between them.
    layout=$(awk '/^## \[Unreleased\]$/ { getline blank; getline heading; printf "%s|%s", blank, heading; exit }' \
        "${repo}/CHANGELOG.md")
    printf '%s\n' "${layout}" | grep -Eq '^\|## \[0\.2\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' ||
        _fail "the dated heading does not sit directly under an empty [Unreleased]: '${layout}'"
    grep -q '^- A thing worth releasing$' "${repo}/CHANGELOG.md" ||
        _fail "an entry was lost"
    grep -q '^### Fixed$' "${repo}/CHANGELOG.md" ||
        _fail "a subsection was lost"
    grep -qF '[0.2.0]: https://github.com/octo/my-app/releases/tag/v0.2.0' "${repo}/CHANGELOG.md" ||
        _fail "the release link reference was not added"
    grep -qF '[Unreleased]: https://github.com/octo/my-app/commits/main' "${repo}/CHANGELOG.md" ||
        _fail "the [Unreleased] link reference was changed"
}

case_writes_no_commit_or_tag() {
    # The whole point of the script: two edited files, left for a human to commit.
    repo=$(make_fixture_repo)
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    [ "$(git -C "${repo}" rev-list --count HEAD)" = "1" ] || _fail "a commit was created"
    [ -z "$(git -C "${repo}" tag)" ] || _fail "a tag was created"
    changed=$(git -C "${repo}" status --porcelain | cut -c4- | sort | tr '\n' ' ')
    [ "${changed}" = "CHANGELOG.md project.yml " ] ||
        _fail "the working tree holds something other than the two edits: '${changed}'"
}

case_prints_the_next_commands() {
    repo=$(make_fixture_repo)
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    assert_stdout_contains "git add project.yml CHANGELOG.md"
    assert_stdout_contains "git commit -m 'chore(release): 0.2.0'"
    assert_stdout_contains "gh pr create --fill"
    # The tag the release workflow checks against MARKETING_VERSION, pushed last.
    assert_stdout_contains "git tag v0.2.0"
    assert_stdout_contains "git push origin v0.2.0"
    assert_stdout_contains "No commit, tag, or push was created."
}

case_dry_run_writes_nothing() {
    repo=$(make_fixture_repo)
    watch_file "${repo}/project.yml"
    watch_file "${repo}/CHANGELOG.md"
    capture "${RELEASE_PREP_SH}" --root "${repo}" --dry-run 0.2.0
    assert_exit 0
    assert_stdout_contains "MARKETING_VERSION 0.1.0 -> 0.2.0"
    assert_stdout_contains "--dry-run, nothing was written"
    assert_file_unchanged "${repo}/project.yml"
    assert_file_unchanged "${repo}/CHANGELOG.md"
    [ -z "$(git -C "${repo}" status --porcelain)" ] || _fail "a dry run left the tree dirty"
}

case_compares_components_as_numbers() {
    # The case a string comparison gets wrong.
    repo=$(make_fixture_repo 1.9.0 7)
    capture "${RELEASE_PREP_SH}" --root "${repo}" 1.10.0
    assert_exit 0
    [ "$(setting "${repo}/project.yml" MARKETING_VERSION)" = "1.10.0" ] ||
        _fail "1.10.0 was not accepted over 1.9.0"
    [ "$(setting "${repo}/project.yml" CURRENT_PROJECT_VERSION)" = "8" ] ||
        _fail "CURRENT_PROJECT_VERSION was not incremented to 8"
}

case_refuses_a_version_that_is_not_greater() {
    repo=$(make_fixture_repo 1.10.0 1)
    capture "${RELEASE_PREP_SH}" --root "${repo}" 1.9.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_NOT_GREATER"
    [ "$(setting "${repo}/project.yml" MARKETING_VERSION)" = "1.10.0" ] ||
        _fail "the manifest was written despite the refusal"
}

case_refuses_the_current_version() {
    repo=$(make_fixture_repo)
    watch_file "${repo}/CHANGELOG.md"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.1.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_NOT_GREATER"
    assert_stderr_contains "already the current version"
    assert_file_unchanged "${repo}/CHANGELOG.md"
    head -n 1 "${CASE_DIR}/stderr" | grep -q '^ERR_RELEASE_NOT_GREATER: ' ||
        _fail "the first stderr line is not the failure code"
    assert_stderr_contains "Expected: "
    assert_stderr_contains "Actual: "
    assert_stderr_contains "Next: "
}

case_refuses_a_dirty_tree() {
    repo=$(make_fixture_repo)
    echo "work in progress" >"${repo}/README.md"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_DIRTY_TREE"
    assert_stderr_contains "README.md"
    [ "$(setting "${repo}/project.yml" MARKETING_VERSION)" = "0.1.0" ] ||
        _fail "the manifest was written despite the refusal"
}

case_refuses_a_dirty_tree_in_a_dry_run() {
    # A dry run that passes must mean a real run passes, so it checks the tree too.
    repo=$(make_fixture_repo)
    echo "work in progress" >"${repo}/README.md"
    capture "${RELEASE_PREP_SH}" --root "${repo}" --dry-run 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_DIRTY_TREE"
}

case_refuses_an_empty_unreleased_section() {
    repo=$(make_temp_repo)
    write_manifest "${repo}" 0.1.0 1
    cat >"${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added

## [0.1.0] - 2026-01-01

- The first release

[Unreleased]: https://github.com/octo/my-app/commits/main
EOF
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_CHANGELOG_EMPTY"
}

case_refuses_a_changelog_without_an_unreleased_heading() {
    repo=$(make_temp_repo)
    write_manifest "${repo}" 0.1.0 1
    printf '# Changelog\n\n## [0.1.0] - 2026-01-01\n\n- The first release\n' >"${repo}/CHANGELOG.md"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_CHANGELOG_SHAPE"
}

case_refuses_a_version_the_changelog_already_has() {
    repo=$(make_temp_repo)
    write_manifest "${repo}" 0.1.0 1
    cat >"${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- Something new

## [0.2.0] - 2026-01-01

- Released already, but the manifest was never bumped
EOF
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_CHANGELOG_DUPLICATE"
}

case_leaves_an_unknown_link_reference_alone() {
    repo=$(make_temp_repo)
    write_manifest "${repo}" 0.1.0 1
    cat >"${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- Something new

[Unreleased]: ./NOTES.md
EOF
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    grep -qF '[Unreleased]: ./NOTES.md' "${repo}/CHANGELOG.md" ||
        _fail "the unrecognized link reference was rewritten"
    ! grep -q '^\[0\.2\.0\]:' "${repo}/CHANGELOG.md" ||
        _fail "a link reference was guessed from an unrecognized URL"
    assert_stdout_not_contains "link reference [0.2.0]" "a link reference it did not write"
}

case_ignores_a_git_warning_on_a_clean_tree() {
    # A configured-but-broken hook makes `git status` print a fatal: line to stderr
    # and still exit 0 with a correct, empty listing. Those lines are not changes.
    repo=$(make_fixture_repo)
    git -C "${repo}" config core.fsmonitor /nonexistent-hook
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    assert_stderr_not_contains "nonexistent-hook" "git's warning"
    [ "$(setting "${repo}/project.yml" MARKETING_VERSION)" = "0.2.0" ] ||
        _fail "a warning on a clean tree stopped the release prep"
}

case_writes_a_link_reference_with_no_space_after_the_colon() {
    # The plan and the write must agree about what an [Unreleased]: line is: a
    # Markdown link reference definition needs no space after the colon.
    repo=$(make_temp_repo)
    write_manifest "${repo}" 0.1.0 1
    printf '# Changelog\n\n## [Unreleased]\n\n- Something new\n\n[Unreleased]:https://github.com/octo/my-app/commits/main\n' \
        >"${repo}/CHANGELOG.md"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    assert_stdout_contains "link reference [0.2.0]: https://github.com/octo/my-app/releases/tag/v0.2.0"
    grep -qF '[0.2.0]: https://github.com/octo/my-app/releases/tag/v0.2.0' "${repo}/CHANGELOG.md" ||
        _fail "the plan promised a link reference the write did not add"
}

case_moves_a_compare_range_to_the_new_version() {
    repo=$(make_temp_repo)
    write_manifest "${repo}" 0.1.0 1
    printf '# Changelog\n\n## [Unreleased]\n\n- Something new\n\n[Unreleased]: https://github.com/octo/my-app/compare/v0.1.0...HEAD\n' \
        >"${repo}/CHANGELOG.md"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    # The range names a version, so leaving it at v0.1.0 would make [Unreleased]
    # link to the changes this run just released.
    grep -qF '[Unreleased]: https://github.com/octo/my-app/compare/v0.2.0...HEAD' "${repo}/CHANGELOG.md" ||
        _fail "the compare range was not moved to the new version"
    grep -qF '[0.2.0]: https://github.com/octo/my-app/releases/tag/v0.2.0' "${repo}/CHANGELOG.md" ||
        _fail "the release link reference was not added"
    assert_stdout_contains "link reference [Unreleased]: https://github.com/octo/my-app/compare/v0.2.0...HEAD"
}

case_keeps_a_commits_link_reference_as_it_is() {
    # That shape names no version, so there is nothing in it to move.
    repo=$(make_fixture_repo)
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    grep -qF '[Unreleased]: https://github.com/octo/my-app/commits/main' "${repo}/CHANGELOG.md" ||
        _fail "the commits-shaped [Unreleased] reference was rewritten"
    assert_stdout_not_contains "link reference [Unreleased]" "a rewrite it did not make"
}

case_keeps_unquoted_values_and_comments() {
    repo=$(make_temp_repo)
    cat >"${repo}/project.yml" <<'EOF'
settings:
  base:
    MARKETING_VERSION: 0.1.0   # the user-visible version
    CURRENT_PROJECT_VERSION: 1
EOF
    write_changelog "${repo}"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    grep -q '^    MARKETING_VERSION: 0\.2\.0   # the user-visible version$' "${repo}/project.yml" ||
        _fail "the indentation, quoting style, or trailing comment was not preserved"
    grep -q '^    CURRENT_PROJECT_VERSION: 2$' "${repo}/project.yml" ||
        _fail "the unquoted build number was not rewritten in place"
}

case_leaves_no_temporary_files_behind() {
    repo=$(make_fixture_repo)
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 0
    leftovers=$(find "${repo}" -maxdepth 1 -name '*.release-prep.*' | tr '\n' ' ')
    [ -z "${leftovers}" ] || _fail "temporary files were left behind: ${leftovers}"
}

case_refuses_a_malformed_version() {
    repo=$(make_fixture_repo)
    for bad in 1.2 v1.2.3 1.2.3.4 1.2.3-rc.1 1.2.3+42 01.2.3 "" latest; do
        capture "${RELEASE_PREP_SH}" --root "${repo}" "${bad}"
        assert_exit 1
        # An empty argument is not a version at all, so it is a usage failure.
        if [ -z "${bad}" ]; then
            assert_stderr_contains "ERR_RELEASE_USAGE"
        else
            assert_stderr_contains "ERR_RELEASE_VERSION_INVALID"
        fi
    done
}

case_refuses_a_manifest_without_a_version() {
    repo=$(make_temp_repo)
    printf 'settings:\n  base:\n    CURRENT_PROJECT_VERSION: "1"\n' >"${repo}/project.yml"
    write_changelog "${repo}"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_MANIFEST_VERSION"
}

case_refuses_a_manifest_without_a_build_number() {
    repo=$(make_temp_repo)
    printf 'settings:\n  base:\n    MARKETING_VERSION: "0.1.0"\n' >"${repo}/project.yml"
    write_changelog "${repo}"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "fixture"
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_MANIFEST_BUILD"
}

case_refuses_outside_a_git_work_tree() {
    root=$(make_temp_dir)
    write_manifest "${root}" 0.1.0 1
    write_changelog "${root}"
    capture "${RELEASE_PREP_SH}" --root "${root}" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_NOT_A_REPO"
}

case_refuses_a_root_without_the_two_files() {
    repo=$(make_temp_repo)
    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_INPUT_MISSING"
}

case_usage_failures() {
    repo=$(make_fixture_repo)
    capture "${RELEASE_PREP_SH}" --root "${repo}"
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_USAGE"

    capture "${RELEASE_PREP_SH}" --root "${repo}" --nope 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_USAGE"

    capture "${RELEASE_PREP_SH}" --root "${repo}" 0.2.0 0.3.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_USAGE"

    capture "${RELEASE_PREP_SH}" --root "${TEST_TMP_ROOT}/does-not-exist" 0.2.0
    assert_exit 1
    assert_stderr_contains "ERR_RELEASE_USAGE"
}

run_case "sets the version, bumps the build, and rolls the changelog" case_rolls_the_release
run_case "creates no commit and no tag, only two edited files" case_writes_no_commit_or_tag
run_case "prints the commit, PR, and tag commands" case_prints_the_next_commands
run_case "--dry-run checks everything and writes nothing" case_dry_run_writes_nothing
run_case "compares versions component by component (1.10.0 > 1.9.0)" case_compares_components_as_numbers
run_case "refuses a version below the current one" case_refuses_a_version_that_is_not_greater
run_case "refuses the version already in the manifest" case_refuses_the_current_version
run_case "refuses a dirty work tree" case_refuses_a_dirty_tree
run_case "refuses a dirty work tree even with --dry-run" case_refuses_a_dirty_tree_in_a_dry_run
run_case "refuses an empty [Unreleased] section" case_refuses_an_empty_unreleased_section
run_case "refuses a changelog with no [Unreleased] heading" case_refuses_a_changelog_without_an_unreleased_heading
run_case "refuses a version the changelog already has" case_refuses_a_version_the_changelog_already_has
run_case "leaves a link reference it does not recognize alone" case_leaves_an_unknown_link_reference_alone
run_case "treats a git warning on a clean tree as no change" case_ignores_a_git_warning_on_a_clean_tree
run_case "writes the reference for an [Unreleased]: line with no space" case_writes_a_link_reference_with_no_space_after_the_colon
run_case "moves an [Unreleased]: compare range to the new version" case_moves_a_compare_range_to_the_new_version
run_case "leaves a commits-shaped [Unreleased]: reference alone" case_keeps_a_commits_link_reference_as_it_is
run_case "keeps an unquoted value and its trailing comment" case_keeps_unquoted_values_and_comments
run_case "leaves no temporary files behind" case_leaves_no_temporary_files_behind
run_case "rejects a version that is not MAJOR.MINOR.PATCH" case_refuses_a_malformed_version
run_case "names a manifest with no MARKETING_VERSION" case_refuses_a_manifest_without_a_version
run_case "names a manifest with no CURRENT_PROJECT_VERSION" case_refuses_a_manifest_without_a_build_number
run_case "refuses to run outside a git work tree" case_refuses_outside_a_git_work_tree
run_case "names a root without project.yml and CHANGELOG.md" case_refuses_a_root_without_the_two_files
run_case "rejects a missing, unknown, or doubled argument" case_usage_failures
finish
