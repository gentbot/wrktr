#!/usr/bin/env bats
# Command-level tests for wrktr against a real local origin repository.
#
# Each test gets a fresh origin repo under BATS_TEST_TMPDIR. Tests never reach
# a code path that reads from /dev/tty (which would block in an interactive
# terminal): the remove/push prompts are only exercised via dry-run or the
# guard clauses that return before prompting.
#
# Run:  bats tests/commands.bats

WRKTR_FUNCTIONS="$BATS_TEST_DIRNAME/../worktree-functions.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup() {
    # shellcheck disable=SC1090
    source "$WRKTR_FUNCTIONS" >/dev/null

    local base="${BATS_TEST_TMPDIR:-$BATS_TMPDIR/wrktr-cmd-$$-$BATS_TEST_NUMBER}"
    mkdir -p "$base"
    T="$(cd "$base" && pwd -P)"
    export T

    export WRKTR_CONFIG_DIR="$T/config"
    mkdir -p "$WRKTR_CONFIG_DIR" "$T/proj"
    unset WRKTR_NAME WRKTR_BASE_TRUNK WRKTR_BASE_DIR WRKTR_REMOTE WRKTR_MAIN_BRANCH

    # Isolate from the developer's git config and provide an identity.
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

    ORIGIN="$T/origin"
    TRUNK="$T/proj/app"
    export ORIGIN TRUNK

    git init -q "$ORIGIN"
    git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
    echo a > "$ORIGIN/a"
    git -C "$ORIGIN" add a
    git -C "$ORIGIN" commit -qm "initial"
}

teardown() {
    [ -n "${BATS_TEST_TMPDIR:-}" ] || rm -rf "$T"
}

# Clone origin into $TRUNK, write a session config and load it.
_start_session() {
    wrktr_clone "$ORIGIN" "$TRUNK" >/dev/null 2>&1
    printf 'WRKTR_NAME=app\nWRKTR_BASE_TRUNK=%s\nWRKTR_BASE_DIR=%s/.wrktr\nWRKTR_REMOTE=origin\nWRKTR_MAIN_BRANCH=main\n' \
        "$TRUNK" "$TRUNK" > "$WRKTR_CONFIG_DIR/app.env"
    wrktr_use app >/dev/null 2>&1
}

# Run a script body (from stdin) in a fresh bash with wrktr loaded.
_script() {
    {
        printf 'source "%s" >/dev/null\n' "$WRKTR_FUNCTIONS"
        cat
    } > "$T/script.sh"
    run bash "$T/script.sh"
}

# ---------------------------------------------------------------------------
# wrktr_clone
# ---------------------------------------------------------------------------

@test "wrktr_clone: creates the bare repo and the main worktree" {
    run wrktr_clone "$ORIGIN" "$TRUNK"
    [ "$status" -eq 0 ]
    [ -d "$TRUNK/.wrktr" ]
    [ -f "$TRUNK/main/a" ]
}

@test "wrktr_clone: refuses an existing destination" {
    mkdir -p "$TRUNK"
    run wrktr_clone "$ORIGIN" "$TRUNK"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "already exists" ]]
}

@test "wrktr_clone: dry-run creates nothing" {
    WRKTR_DRY_RUN=1 run wrktr_clone "$ORIGIN" "$TRUNK"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY RUN" ]]
    [ ! -e "$TRUNK" ]
}

@test "wrktr_clone: fails with no URL" {
    run wrktr_clone
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# ---------------------------------------------------------------------------
# wrktr_add
# ---------------------------------------------------------------------------

@test "wrktr_add: creates a worktree and branch from the remote main" {
    _start_session
    _script <<'EOF'
wrktr_add feature/x >/dev/null 2>&1 || exit 10
pwd -P
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TRUNK/feature%2Fx" ]]
    [ -d "$TRUNK/feature%2Fx" ]
    git --git-dir="$TRUNK/.wrktr" show-ref --verify --quiet refs/heads/feature/x
}

@test "wrktr_add: local-only session branches from the main branch" {
    _start_session
    _script <<'EOF'
export WRKTR_REMOTE=
wrktr_add local-work >/dev/null 2>&1 || exit 10
EOF
    [ "$status" -eq 0 ]
    [ -d "$TRUNK/local-work" ]
}

@test "wrktr_add: fails when the branch already exists" {
    _start_session
    git --git-dir="$TRUNK/.wrktr" branch taken main
    run wrktr_add taken
    [ "$status" -eq 1 ]
    [[ "$output" =~ "already exists" ]]
}

@test "wrktr_add: fails for a base ref that does not exist" {
    _start_session
    run wrktr_add feature/y no-such-ref
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Base ref does not exist" ]]
    [ ! -d "$TRUNK/feature%2Fy" ]
}

@test "wrktr_add: dry-run creates nothing" {
    _start_session
    WRKTR_DRY_RUN=1 run wrktr_add feature/d
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY RUN" ]]
    [ ! -d "$TRUNK/feature%2Fd" ]
}

# ---------------------------------------------------------------------------
# wrktr_go / wrktr_base
# ---------------------------------------------------------------------------

@test "wrktr_go: changes into the worktree for a branch" {
    _start_session
    _script <<'EOF'
wrktr_add feature/g >/dev/null 2>&1 || exit 10
cd / || exit 11
wrktr_go feature/g >/dev/null 2>&1 || exit 12
pwd -P
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TRUNK/feature%2Fg" ]]
}

@test "wrktr_go: fails when no worktree exists for the branch" {
    _start_session
    run wrktr_go nothing-here
    [ "$status" -eq 1 ]
    [[ "$output" =~ "No worktree found" ]]
}

@test "wrktr_base: changes into the trunk directory" {
    _start_session
    _script <<'EOF'
cd / || exit 10
wrktr_base >/dev/null 2>&1 || exit 11
pwd -P
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "$TRUNK" ]
}

# ---------------------------------------------------------------------------
# wrktr_status / wrktr_prompt_info
# ---------------------------------------------------------------------------

@test "wrktr_status: lists worktrees and flags uncommitted changes" {
    _start_session
    echo changed >> "$TRUNK/main/a"
    run wrktr_status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "branch: main" ]]
    [[ "$output" =~ "[dirty]" ]]
}

@test "wrktr_status: fails with no session loaded" {
    run wrktr_status
    [ "$status" -eq 1 ]
}

@test "wrktr_prompt_info: prints nothing with no session" {
    run wrktr_prompt_info
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "wrktr_prompt_info: prints session and branch inside a worktree" {
    _start_session
    _script <<'EOF'
cd "$TRUNK/main" || exit 10
wrktr_prompt_info
EOF
    [ "$status" -eq 0 ]
    [ "$output" = "[app:main]" ]
}

# ---------------------------------------------------------------------------
# wrktr_update
# ---------------------------------------------------------------------------

@test "wrktr_update: fetches new commits from the remote" {
    _start_session
    git -C "$ORIGIN" commit --allow-empty -qm "new upstream commit"
    run wrktr_update
    [ "$status" -eq 0 ]
    [ "$(git --git-dir="$TRUNK/.wrktr" rev-parse origin/main)" = "$(git -C "$ORIGIN" rev-parse main)" ]
}

@test "wrktr_update: skips when no remote is configured" {
    _start_session
    export WRKTR_REMOTE=
    run wrktr_update
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No remote configured" ]]
}

# ---------------------------------------------------------------------------
# wrktr_checkout
# ---------------------------------------------------------------------------

@test "wrktr_checkout: creates a tracking worktree for a remote branch" {
    _start_session
    git -C "$ORIGIN" branch feature/y main
    _script <<'EOF'
wrktr_checkout feature/y >/dev/null 2>&1 || exit 10
EOF
    [ "$status" -eq 0 ]
    [ -d "$TRUNK/feature%2Fy" ]
    [ "$(git --git-dir="$TRUNK/.wrktr" rev-parse --abbrev-ref 'feature/y@{upstream}')" = "origin/feature/y" ]
}

@test "wrktr_checkout: fails for a branch that is not on the remote" {
    _start_session
    run wrktr_checkout does-not-exist
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Remote branch not found" ]]
}

@test "wrktr_checkout: fails when no remote is configured" {
    _start_session
    export WRKTR_REMOTE=
    run wrktr_checkout feature/y
    [ "$status" -eq 1 ]
    [[ "$output" =~ "No remote configured" ]]
}

# ---------------------------------------------------------------------------
# wrktr_remote_add
# ---------------------------------------------------------------------------

@test "wrktr_remote_add: adds a remote with the bare-repo fetch refspec" {
    _start_session
    run wrktr_remote_add upstream "$ORIGIN"
    [ "$status" -eq 0 ]
    [ "$(git --git-dir="$TRUNK/.wrktr" config --get remote.upstream.fetch)" = "+refs/heads/*:refs/remotes/upstream/*" ]
}

@test "wrktr_remote_add: refuses a remote name that already exists" {
    _start_session
    run wrktr_remote_add origin "$ORIGIN"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "already exists" ]]
}

@test "wrktr_remote_add: fails without both arguments" {
    _start_session
    run wrktr_remote_add onlyname
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# ---------------------------------------------------------------------------
# wrktr_rebase
# ---------------------------------------------------------------------------

@test "wrktr_rebase: rebases the current branch onto the updated remote main" {
    _start_session
    _script <<'EOF'
wrktr_add feature/r >/dev/null 2>&1 || exit 10
echo b > b && git add b && git commit -qm "feature commit" || exit 11
git -C "$ORIGIN" commit --allow-empty -qm "upstream commit" || exit 12
wrktr_rebase >/dev/null 2>&1 || exit 13
git log --format=%s
EOF
    [ "$status" -eq 0 ]
    [[ "$output" =~ "upstream commit" ]]
    [[ "$output" =~ "feature commit" ]]
}

@test "wrktr_rebase: refuses to rebase the main branch" {
    _start_session
    _script <<'EOF'
cd "$TRUNK/main" || exit 10
wrktr_rebase
EOF
    [ "$status" -eq 1 ]
    [[ "$output" =~ "refusing to rebase" ]]
}

@test "wrktr_rebase: refuses a dirty working tree" {
    _start_session
    _script <<'EOF'
wrktr_add feature/dirty >/dev/null 2>&1 || exit 10
echo x > untracked
wrktr_rebase
EOF
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Working tree is dirty" ]]
}

# ---------------------------------------------------------------------------
# wrktr_push (guard clauses and the success path; never reaches the prompt)
# ---------------------------------------------------------------------------

@test "wrktr_push: pushes the current branch to the remote" {
    _start_session
    _script <<'EOF'
wrktr_add feature/p >/dev/null 2>&1 || exit 10
echo p > p && git add p && git commit -qm "push me" || exit 11
wrktr_push >/dev/null 2>&1 || exit 12
git -C "$ORIGIN" rev-parse --verify --quiet refs/heads/feature/p
EOF
    [ "$status" -eq 0 ]
}

@test "wrktr_push: refuses to push the main branch" {
    _start_session
    _script <<'EOF'
cd "$TRUNK/main" || exit 10
wrktr_push
EOF
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Refusing to push the main branch" ]]
}

@test "wrktr_push: fails when no remote is configured" {
    _start_session
    _script <<'EOF'
export WRKTR_REMOTE=
cd "$TRUNK/main" || exit 10
wrktr_push
EOF
    [ "$status" -eq 1 ]
    [[ "$output" =~ "No remote configured" ]]
}

@test "wrktr_push: fails outside a worktree of the session" {
    _start_session
    _script <<'EOF'
cd / || exit 10
wrktr_push
EOF
    [ "$status" -eq 1 ]
    [[ "$output" =~ "inside a git worktree" ]]
}

# ---------------------------------------------------------------------------
# wrktr_remove (dry-run only; the real path prompts on /dev/tty)
# ---------------------------------------------------------------------------

@test "wrktr_remove: dry-run leaves the worktree in place" {
    _start_session
    _script <<'EOF'
wrktr_add feature/keep >/dev/null 2>&1 || exit 10
cd "$TRUNK" || exit 11
wrktr_dryrun_enable >/dev/null
wrktr_remove feature/keep
EOF
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY RUN" ]]
    [ -d "$TRUNK/feature%2Fkeep" ]
}

# ---------------------------------------------------------------------------
# Session and dry-run helpers
# ---------------------------------------------------------------------------

@test "wrktr_git: runs git against the bare repository" {
    _start_session
    run wrktr_git rev-parse --is-bare-repository
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "wrktr_list: shows available sessions" {
    _start_session
    run wrktr_list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "app" ]]
}

@test "wrktr_current: shows the loaded session" {
    _start_session
    run wrktr_current
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Name:         app" ]]
    [[ "$output" =~ "Main branch:  main" ]]
}

@test "wrktr_config_show: prints the session config" {
    _start_session
    run wrktr_config_show
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WRKTR_NAME=app" ]]
}

@test "wrktr_dryrun_enable / disable / status toggle dry-run mode" {
    _script <<'EOF'
wrktr_dryrun_enable >/dev/null
wrktr_dryrun_status
wrktr_dryrun_disable >/dev/null
wrktr_dryrun_status
EOF
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ENABLED" ]]
    [[ "$output" =~ "DISABLED" ]]
}
