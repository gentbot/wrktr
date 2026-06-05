#!/usr/bin/env bats
# Test suite for wrktr shell functions.
#
# Requirements: bats-core >= 1.2 (https://github.com/bats-core/bats-core)
#
#   brew install bats-core   # macOS
#   apt install bats         # Debian/Ubuntu
#
# Run all tests:
#   bats tests/
#
# Run a single file:
#   bats tests/wrktr.bats

WRKTR_FUNCTIONS="$BATS_TEST_DIRNAME/../worktree-functions.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a minimal bare git repository and export session env vars.
_make_bare_repo() {
    local trunk="$1"
    local repo="$trunk/.wrktr"
    mkdir -p "$repo"
    git init --bare "$repo" >/dev/null 2>&1
    export WRKTR_NAME="testproject"
    export WRKTR_BASE_TRUNK="$trunk"
    export WRKTR_BASE_DIR="$repo"
    export WRKTR_REMOTE=""
    export WRKTR_MAIN_BRANCH="main"
}

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

setup() {
    # Source fresh for each test
    # shellcheck disable=SC1090
    source "$WRKTR_FUNCTIONS"

    # Redirect to an isolated config directory so tests never touch ~/.config
    export WRKTR_CONFIG_DIR="$BATS_TMPDIR/wrktr-configs-$$-$RANDOM"
    mkdir -p "$WRKTR_CONFIG_DIR"

    # Clear any session state left from a previous test
    unset WRKTR_NAME WRKTR_BASE_TRUNK WRKTR_BASE_DIR WRKTR_REMOTE WRKTR_MAIN_BRANCH
}

teardown() {
    rm -rf "$WRKTR_CONFIG_DIR"
    rm -rf "$BATS_TMPDIR/wrktr-trunk-$$-"*
    rm -rf "$BATS_TMPDIR/wrktr-parent-$$"
    rm -rf "$BATS_TMPDIR/wrktr-outside-$$"
}

# ===========================================================================
# _wrktr_sanitize_branch_name
# ===========================================================================

@test "_wrktr_sanitize_branch_name: plain name is unchanged" {
    result="$(_wrktr_sanitize_branch_name "main")"
    [ "$result" = "main" ]
}

@test "_wrktr_sanitize_branch_name: single slash encoded as %2F" {
    result="$(_wrktr_sanitize_branch_name "feature/login")"
    [ "$result" = "feature%2Flogin" ]
}

@test "_wrktr_sanitize_branch_name: multiple slashes all encoded" {
    result="$(_wrktr_sanitize_branch_name "a/b/c")"
    [ "$result" = "a%2Fb%2Fc" ]
}

@test "_wrktr_sanitize_branch_name: percent encoded before slash to avoid double-encoding" {
    result="$(_wrktr_sanitize_branch_name "fix/crash-100%")"
    [ "$result" = "fix%2Fcrash-100%25" ]
}

@test "_wrktr_sanitize_branch_name: existing percent-sign is escaped first" {
    result="$(_wrktr_sanitize_branch_name "already%2Fencoded")"
    [ "$result" = "already%252Fencoded" ]
}

# ===========================================================================
# _wrktr_assert_subpath
# ===========================================================================

@test "_wrktr_assert_subpath: direct child passes" {
    local parent="$BATS_TMPDIR/wrktr-parent-$$"
    local child="$parent/child"
    mkdir -p "$child"
    run _wrktr_assert_subpath "$parent" "$child"
    [ "$status" -eq 0 ]
}

@test "_wrktr_assert_subpath: deep nested child passes" {
    local parent="$BATS_TMPDIR/wrktr-parent-$$"
    local deep="$parent/a/b/c"
    mkdir -p "$deep"
    run _wrktr_assert_subpath "$parent" "$deep"
    [ "$status" -eq 0 ]
}

@test "_wrktr_assert_subpath: path outside parent root fails" {
    local parent="$BATS_TMPDIR/wrktr-parent-$$"
    local outside="$BATS_TMPDIR/wrktr-outside-$$"
    mkdir -p "$parent"
    mkdir -p "$outside"
    run _wrktr_assert_subpath "$parent" "$outside/thing"
    [ "$status" -eq 1 ]
}

@test "_wrktr_assert_subpath: nonexistent parent fails" {
    run _wrktr_assert_subpath "/nonexistent/path/$$" "/nonexistent/path/$$/child"
    [ "$status" -eq 1 ]
}

@test "_wrktr_assert_subpath: path traversal via .. fails" {
    local parent="$BATS_TMPDIR/wrktr-parent-$$"
    local escape="$BATS_TMPDIR/wrktr-outside-$$"
    mkdir -p "$parent"
    mkdir -p "$escape"
    # ../outside resolves to a sibling of parent, which is outside
    run _wrktr_assert_subpath "$parent" "$parent/../wrktr-outside-$$/thing"
    [ "$status" -eq 1 ]
}

# ===========================================================================
# wrktr_validate
# ===========================================================================

@test "wrktr_validate: fails when no session is loaded" {
    unset WRKTR_NAME WRKTR_BASE_TRUNK WRKTR_BASE_DIR WRKTR_REMOTE WRKTR_MAIN_BRANCH
    run wrktr_validate
    [ "$status" -eq 1 ]
}

@test "wrktr_validate: fails when WRKTR_NAME is missing" {
    export WRKTR_BASE_DIR="/tmp" WRKTR_MAIN_BRANCH="main"
    unset WRKTR_NAME
    run wrktr_validate
    [ "$status" -eq 1 ]
}

@test "wrktr_validate: fails when WRKTR_BASE_TRUNK is missing" {
    export WRKTR_NAME="test" WRKTR_BASE_DIR="/tmp" WRKTR_MAIN_BRANCH="main"
    unset WRKTR_BASE_TRUNK
    run wrktr_validate
    [ "$status" -eq 1 ]
}

@test "wrktr_validate: fails when WRKTR_BASE_DIR is missing" {
    export WRKTR_NAME="test" WRKTR_BASE_TRUNK="/tmp" WRKTR_MAIN_BRANCH="main"
    unset WRKTR_BASE_DIR
    run wrktr_validate
    [ "$status" -eq 1 ]
}

@test "wrktr_validate: fails when WRKTR_MAIN_BRANCH is missing" {
    export WRKTR_NAME="test" WRKTR_BASE_TRUNK="/tmp" WRKTR_BASE_DIR="/tmp"
    unset WRKTR_MAIN_BRANCH
    run wrktr_validate
    [ "$status" -eq 1 ]
}

@test "wrktr_validate: fails when WRKTR_BASE_TRUNK does not exist" {
    local nonexistent="/tmp/wrktr-noexist-$$-$RANDOM"
    export WRKTR_NAME="test"
    export WRKTR_BASE_TRUNK="$nonexistent"
    export WRKTR_BASE_DIR="/tmp"
    export WRKTR_MAIN_BRANCH="main"
    run wrktr_validate
    [ "$status" -eq 1 ]
}

@test "wrktr_validate: fails when WRKTR_BASE_DIR does not exist" {
    local nonexistent="/tmp/wrktr-noexist-$$-$RANDOM"
    export WRKTR_NAME="test"
    export WRKTR_BASE_TRUNK="/tmp"
    export WRKTR_BASE_DIR="$nonexistent"
    export WRKTR_MAIN_BRANCH="main"
    run wrktr_validate
    [ "$status" -eq 1 ]
}

@test "wrktr_validate: fails when WRKTR_BASE_DIR is not a git directory" {
    local trunk="$BATS_TMPDIR/wrktr-trunk-$$-$RANDOM"
    local notgit="$trunk/notgit"
    mkdir -p "$notgit"
    export WRKTR_NAME="test"
    export WRKTR_BASE_TRUNK="$trunk"
    export WRKTR_BASE_DIR="$notgit"
    export WRKTR_MAIN_BRANCH="main"
    run wrktr_validate
    [ "$status" -eq 1 ]
}

@test "wrktr_validate: passes with a valid bare repository" {
    local trunk="$BATS_TMPDIR/wrktr-trunk-$$-$RANDOM"
    _make_bare_repo "$trunk"
    run wrktr_validate
    [ "$status" -eq 0 ]
}

@test "wrktr_validate: passes without a remote configured" {
    local trunk="$BATS_TMPDIR/wrktr-trunk-$$-$RANDOM"
    _make_bare_repo "$trunk"
    export WRKTR_REMOTE=""
    run wrktr_validate
    [ "$status" -eq 0 ]
}

# ===========================================================================
# wrktr_use
# ===========================================================================

@test "wrktr_use: fails with no argument" {
    run wrktr_use
    [ "$status" -eq 1 ]
}

@test "wrktr_use: fails with invalid session name (slash)" {
    run wrktr_use "path/traversal"
    [ "$status" -eq 1 ]
}

@test "wrktr_use: fails with invalid session name (dotdot)" {
    run wrktr_use "../escape"
    [ "$status" -eq 1 ]
}

@test "wrktr_use: fails when config file does not exist" {
    run wrktr_use "nonexistent-session-$$"
    [ "$status" -eq 1 ]
}

@test "wrktr_use: loads a valid KEY=value config" {
    local trunk="$BATS_TMPDIR/wrktr-trunk-$$-$RANDOM"
    _make_bare_repo "$trunk"

    cat > "$WRKTR_CONFIG_DIR/testproject.env" <<EOF
WRKTR_NAME=testproject
WRKTR_BASE_TRUNK=$trunk
WRKTR_BASE_DIR=$trunk/.wrktr
WRKTR_REMOTE=
WRKTR_MAIN_BRANCH=main
EOF

    run wrktr_use "testproject"
    [ "$status" -eq 0 ]
}

@test "wrktr_use: ignores comment lines and blank lines in config" {
    local trunk="$BATS_TMPDIR/wrktr-trunk-$$-$RANDOM"
    _make_bare_repo "$trunk"

    cat > "$WRKTR_CONFIG_DIR/testproject.env" <<EOF
# wrktr session config

WRKTR_NAME=testproject
WRKTR_BASE_TRUNK=$trunk

WRKTR_BASE_DIR=$trunk/.wrktr
WRKTR_REMOTE=
WRKTR_MAIN_BRANCH=main
EOF

    run wrktr_use "testproject"
    [ "$status" -eq 0 ]
}

@test "wrktr_use: rejects config when validation fails" {
    cat > "$WRKTR_CONFIG_DIR/broken.env" <<EOF
WRKTR_NAME=broken
WRKTR_BASE_TRUNK=/nonexistent/path/$$
WRKTR_BASE_DIR=/nonexistent/path/$$/.wrktr
WRKTR_REMOTE=
WRKTR_MAIN_BRANCH=main
EOF

    run wrktr_use "broken"
    [ "$status" -eq 1 ]
}

# ===========================================================================
# wrktr_generate (dry-run output)
# ===========================================================================

@test "wrktr_generate: --help exits 0" {
    run wrktr_generate --help
    [ "$status" -eq 0 ]
}

# ===========================================================================
# wrktr_remove
# ===========================================================================

@test "wrktr_remove: --help exits 0" {
    run wrktr_remove --help
    [ "$status" -eq 0 ]
}

@test "wrktr_remove: fails when no session is loaded" {
    unset WRKTR_NAME WRKTR_BASE_TRUNK WRKTR_BASE_DIR WRKTR_REMOTE WRKTR_MAIN_BRANCH
    run wrktr_remove "feature/test"
    [ "$status" -eq 1 ]
}

@test "wrktr_remove: refuses to remove main branch" {
    local trunk="$BATS_TMPDIR/wrktr-trunk-$$-$RANDOM"
    _make_bare_repo "$trunk"
    # wrktr_remove runs in a subshell via `run`, inherit exported vars
    run wrktr_remove "main"
    [ "$status" -eq 1 ]
}

@test "wrktr_remove: fails with no argument" {
    local trunk="$BATS_TMPDIR/wrktr-trunk-$$-$RANDOM"
    _make_bare_repo "$trunk"
    run wrktr_remove
    [ "$status" -eq 1 ]
}

# ===========================================================================
# Version
# ===========================================================================

@test "WRKTR_VERSION is set after sourcing" {
    [ -n "$WRKTR_VERSION" ]
}

@test "WRKTR_VERSION matches semver format" {
    [[ "$WRKTR_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
