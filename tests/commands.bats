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

# ===========================================================================
# Low-priority hardening
# ===========================================================================

# Run a bash command inside a pty and type $2 at it.
_pty() {
    command -v python3 >/dev/null 2>&1 || skip "python3 not available"
    run python3 "$BATS_TEST_DIRNAME/helpers/run_in_pty.py" \
        "source \"$WRKTR_FUNCTIONS\" >/dev/null; $1" "$2"
}

# Point the loaded session's remote at a path that does not exist (offline).
_break_remote() {
    git --git-dir="$TRUNK/.wrktr" config remote.origin.url "$T/does-not-exist"
}

# ---------------------------------------------------------------------------
# wrktr_push: failure handling and upstream
# ---------------------------------------------------------------------------

@test "wrktr_push: sets the upstream branch on push" {
    _start_session
    _script <<'EOS'
wrktr_add feature/u >/dev/null 2>&1 || exit 10
echo u > u && git add u && git commit -qm u || exit 11
wrktr_push >/dev/null 2>&1 || exit 12
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
EOS
    [ "$status" -eq 0 ]
    [ "$output" = "origin/feature/u" ]
}

@test "wrktr_push: a non-rejection failure does not offer a force push" {
    _start_session
    _script <<'EOS'
wrktr_add feature/bad >/dev/null 2>&1 || exit 10
echo b > b && git add b && git commit -qm b || exit 11
git --git-dir="$WRKTR_BASE_DIR" config remote.origin.url "$T/does-not-exist"
wrktr_push
EOS
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Push failed" ]]
    [[ ! "$output" =~ "rejected" ]]
    [[ ! "$output" =~ "force-with-lease" ]]
}

# ---------------------------------------------------------------------------
# Offline: add/checkout fall back to already-fetched refs
# ---------------------------------------------------------------------------

@test "wrktr_add: falls back to local refs when the fetch fails" {
    _start_session
    _break_remote
    _script <<'EOS'
wrktr_add feature/off >/dev/null 2>&1 || exit 10
pwd -P
EOS
    [ "$status" -eq 0 ]
    [ -d "$TRUNK/feature%2Foff" ]
}

@test "wrktr_checkout: falls back to fetched refs when the fetch fails" {
    _start_session
    git -C "$ORIGIN" branch feature/co main
    wrktr_update >/dev/null 2>&1
    _break_remote
    _script <<'EOS'
wrktr_checkout feature/co >/dev/null 2>&1 || exit 10
EOS
    [ "$status" -eq 0 ]
    [ -d "$TRUNK/feature%2Fco" ]
}

@test "wrktr_add: still fails offline when the base ref was never fetched" {
    _start_session
    _break_remote
    run wrktr_add feature/x never-fetched
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Base ref does not exist" ]]
}

# ---------------------------------------------------------------------------
# wrktr_status: detached worktrees
# ---------------------------------------------------------------------------

@test "wrktr_status: detached worktree is compared from its own HEAD" {
    _start_session
    git -C "$ORIGIN" commit --allow-empty -qm c2
    git -C "$ORIGIN" commit --allow-empty -qm c3
    wrktr_update >/dev/null 2>&1
    local c2
    c2="$(git -C "$ORIGIN" rev-parse HEAD~1)"
    git --git-dir="$TRUNK/.wrktr" worktree add --detach "$TRUNK/det" "$c2" >/dev/null 2>&1
    run wrktr_status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "branch: detached  (-1 behind origin/main)" ]]
}

# ---------------------------------------------------------------------------
# wrktr_clone: URLs that look like options
# ---------------------------------------------------------------------------

@test "wrktr_clone: a URL starting with '-' is treated as a repository, not an option" {
    run wrktr_clone "--upload-pack=touch $T/pwned" "$TRUNK"
    [ "$status" -eq 1 ]
    [ ! -e "$T/pwned" ]
    [ ! -e "$TRUNK" ]
}

# ---------------------------------------------------------------------------
# wrktr_generate: tilde expansion
# ---------------------------------------------------------------------------

@test "wrktr_generate: expands ~ in the trunk path" {
    _start_session
    printf '~/proj/app\n\n\n' > "$T/answers"
    HOME="$T" run wrktr_generate second < "$T/answers"
    [ "$status" -eq 0 ]
    grep -qx "WRKTR_BASE_TRUNK=$TRUNK" "$WRKTR_CONFIG_DIR/second.env"
}

# ---------------------------------------------------------------------------
# Startup output
# ---------------------------------------------------------------------------

@test "sourcing is silent by default and returns success" {
    run bash -c "source \"$WRKTR_FUNCTIONS\"; echo rc=\$?"
    [ "$output" = "rc=0" ]
}

@test "sourcing prints the banner when WRKTR_VERBOSE=1" {
    WRKTR_VERBOSE=1 run bash -c "source \"$WRKTR_FUNCTIONS\""
    [[ "$output" =~ "Worktree functions loaded" ]]
}

# ---------------------------------------------------------------------------
# wrktr_git dry-run: read-only commands still run
# ---------------------------------------------------------------------------

@test "wrktr_git: read-only commands run even in dry-run mode" {
    _start_session
    WRKTR_DRY_RUN=1 run wrktr_git rev-parse --is-bare-repository
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "wrktr_git: mutating commands are still only printed in dry-run mode" {
    _start_session
    WRKTR_DRY_RUN=1 run wrktr_git branch should-not-exist main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY RUN" ]]
    ! git --git-dir="$TRUNK/.wrktr" show-ref --verify --quiet refs/heads/should-not-exist
}

# ---------------------------------------------------------------------------
# wrktr_reload
# ---------------------------------------------------------------------------

@test "wrktr_reload: keeps the loaded session, dry-run state and config dir" {
    _start_session
    _script <<'EOS'
export WRKTR_CONFIG_DIR="$T/config"
wrktr_use app >/dev/null 2>&1 || exit 10
wrktr_dryrun_enable >/dev/null
wrktr_reload >/dev/null 2>&1 || exit 11
printf '%s|%s|%s|%s\n' "$WRKTR_NAME" "$WRKTR_DRY_RUN" "$WRKTR_CONFIG_DIR" "$WRKTR_MAIN_BRANCH"
EOS
    [ "$status" -eq 0 ]
    [ "$output" = "app|1|$T/config|main" ]
}

@test "wrktr_reload: a file with a syntax error leaves the current functions in place" {
    cp "$WRKTR_FUNCTIONS" "$T/wf.sh"
    _script <<EOS
source "$T/wf.sh" >/dev/null
printf 'if then fi\n' >> "$T/wf.sh"
wrktr_reload >/dev/null 2>&1
rc=\$?
type wrktr_use >/dev/null 2>&1 && echo "still-defined rc=\$rc"
EOS
    [ "$status" -eq 0 ]
    [ "$output" = "still-defined rc=1" ]
}

# ---------------------------------------------------------------------------
# wrktr_status guard for a stray flag: docs stay in sync with the code
# ---------------------------------------------------------------------------

@test "docs: every public function is documented in docs/wrktr.md" {
    local missing="" fn
    for fn in $(grep -oE '^function wrktr_[a-z_]+' "$WRKTR_FUNCTIONS" | sed 's/function //'); do
        grep -q "$fn" "$BATS_TEST_DIRNAME/../docs/wrktr.md" || missing="$missing $fn"
    done
    [ -z "$missing" ] || { echo "undocumented:$missing"; return 1; }
}

@test "docs: no placeholder clone URL in README, reference or man page" {
    ! grep -rq 'your-username' "$BATS_TEST_DIRNAME/../README.md" "$BATS_TEST_DIRNAME/../docs"
}

@test "docs: man page has no lint errors or warnings" {
    command -v mandoc >/dev/null 2>&1 || skip "mandoc not available"
    run bash -c "mandoc -Tlint \"$BATS_TEST_DIRNAME/../docs/wrktr.1\" 2>&1 | grep -v STYLE"
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# wrktr_adopt (pty)
# ---------------------------------------------------------------------------

_make_existing_clone() {
    git clone -q "$ORIGIN" "$T/existing"
}

@test "wrktr_adopt: restores every remote of the original clone" {
    _make_existing_clone
    git -C "$T/existing" remote add upstream "$ORIGIN"
    _pty "wrktr_adopt \"$T/existing\"" $'\n'"$T/adopted"$'\n\n'
    [ "$status" -eq 0 ]
    git --git-dir="$T/adopted/.wrktr" remote | grep -qx origin
    git --git-dir="$T/adopted/.wrktr" remote | grep -qx upstream
    [ "$(git --git-dir="$T/adopted/.wrktr" config --get remote.upstream.fetch)" = "+refs/heads/*:refs/remotes/upstream/*" ]
}

@test "wrktr_adopt: warns about uncommitted changes and aborts on 'n'" {
    _make_existing_clone
    echo dirty >> "$T/existing/a"
    _pty "wrktr_adopt \"$T/existing\"" $'\n'"$T/adopted"$'\n\nn\n'
    [ "$status" -eq 1 ]
    [[ "$output" =~ "uncommitted" ]]
    [ ! -e "$T/adopted" ]
}

@test "wrktr_adopt: proceeds after the warning when the answer is 'y'" {
    _make_existing_clone
    echo dirty >> "$T/existing/a"
    _pty "wrktr_adopt \"$T/existing\"" $'\n'"$T/adopted"$'\n\ny\n'
    [ "$status" -eq 0 ]
    [ -d "$T/adopted/.wrktr" ]
}

@test "wrktr_adopt: does not leak a global variable" {
    _make_existing_clone
    _pty "wrktr_adopt \"$T/existing\" >/dev/null; echo LEAK=[\${input_branch-unset}]" $'\n'"$T/adopted"$'\n\n'
    [[ "$output" =~ "LEAK=[unset]" ]]
}

# ---------------------------------------------------------------------------
# wrktr_init (pty): declined cleanup and RETURN trap
# ---------------------------------------------------------------------------

@test "wrktr_init: declining removal of the temp dir warns and leaves it in place" {
    mkdir -p "$T/x/main"
    echo f > "$T/x/main/f"
    _pty "wrktr_init" "$T/x"$'\n\n\nn\n'
    [ "$status" -eq 0 ]
    [[ "$output" =~ "was not removed" ]]
    [ -d "$T/x/.wrktr-init-tmp" ]
    [ -f "$T/x/main/f" ]
}

@test "wrktr_init: restores a RETURN trap the caller had set" {
    mkdir -p "$T/x/main"
    echo f > "$T/x/main/f"
    _pty "trap 'true' RETURN; wrktr_init >/dev/null; trap -p RETURN" "$T/x"$'\n\n\ny\n'
    [[ "$output" =~ "trap -- 'true' RETURN" ]]
}

# ---------------------------------------------------------------------------
# wrktr_remove: the real path and its prompts (pty)
# ---------------------------------------------------------------------------

# Create a worktree (and optionally an unmerged commit on it) without leaving
# the test shell's directory.
_make_worktree() {
    ( wrktr_add "$1" >/dev/null 2>&1 )
    [ -d "$TRUNK/$(_wrktr_sanitize_branch_name "$1")" ]
}

@test "wrktr_remove: removes the worktree and keeps the branch on 'n'" {
    _start_session
    _make_worktree feature/r1
    _pty "cd \"$TRUNK\" && wrktr_remove feature/r1" $'n\n'
    [ "$status" -eq 0 ]
    [ ! -d "$TRUNK/feature%2Fr1" ]
    [[ "$output" =~ "Branch kept" ]]
    git --git-dir="$TRUNK/.wrktr" show-ref --verify --quiet refs/heads/feature/r1
}

@test "wrktr_remove: deletes a merged branch on 'y'" {
    _start_session
    _make_worktree feature/r2
    _pty "cd \"$TRUNK\" && wrktr_remove feature/r2" $'y\n'
    [ "$status" -eq 0 ]
    [ ! -d "$TRUNK/feature%2Fr2" ]
    [[ "$output" =~ "Branch feature/r2 deleted" ]]
    ! git --git-dir="$TRUNK/.wrktr" show-ref --verify --quiet refs/heads/feature/r2
}

@test "wrktr_remove: keeps an unmerged branch when the force-delete is declined" {
    _start_session
    _make_worktree feature/r3
    git -C "$TRUNK/feature%2Fr3" commit --allow-empty -qm "unmerged work"
    _pty "cd \"$TRUNK\" && wrktr_remove feature/r3" $'y\nn\n'
    [ "$status" -eq 0 ]
    [ ! -d "$TRUNK/feature%2Fr3" ]
    [[ "$output" =~ "unmerged changes" ]]
    git --git-dir="$TRUNK/.wrktr" show-ref --verify --quiet refs/heads/feature/r3
}

@test "wrktr_remove: force-deletes an unmerged branch only after a second 'y'" {
    _start_session
    _make_worktree feature/r4
    git -C "$TRUNK/feature%2Fr4" commit --allow-empty -qm "unmerged work"
    _pty "cd \"$TRUNK\" && wrktr_remove feature/r4" $'y\ny\n'
    [ "$status" -eq 0 ]
    [[ "$output" =~ "force-deleted" ]]
    ! git --git-dir="$TRUNK/.wrktr" show-ref --verify --quiet refs/heads/feature/r4
}

@test "wrktr_remove: refuses a worktree with uncommitted files and leaves it in place" {
    _start_session
    _make_worktree feature/r5
    echo dirty > "$TRUNK/feature%2Fr5/untracked"
    _pty "cd \"$TRUNK\" && wrktr_remove feature/r5" $'n\n'
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Worktree remove failed" ]]
    [ -f "$TRUNK/feature%2Fr5/untracked" ]
}

# ---------------------------------------------------------------------------
# Help, man page and reference stay in step with behavior
# ---------------------------------------------------------------------------

@test "help: wrktr_use describes parsing and session restore, not sourcing" {
    run wrktr_help use
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Sources" ]]
    [[ "$output" =~ "previously loaded session" ]]
}

@test "help: wrktr_push mentions upstream tracking and force only after a rejection" {
    run wrktr_help push
    [[ "$output" =~ "-u" ]]
    [[ "$output" =~ "rejected" ]]
}

@test "help: wrktr_adopt mentions every remote and uncommitted changes" {
    run wrktr_help adopt
    [[ "$output" =~ "remote" ]]
    [[ "$output" =~ "uncommitted" ]]
}

@test "help: wrktr_reload says it keeps the session" {
    run wrktr_help reload
    [[ "$output" =~ "session" ]]
    [[ "$output" =~ "syntax" ]]
}

@test "help: wrktr_git says read-only commands run in dry-run mode" {
    run wrktr_help git
    [[ "$output" =~ "dry-run" ]]
}

@test "help: wrktr_add and wrktr_checkout mention the offline fallback" {
    run wrktr_help add
    [[ "$output" =~ "fetch fails" ]]
    run wrktr_help checkout
    [[ "$output" =~ "fetch fails" ]]
}

@test "docs: reference no longer says wrktr_use sources configs" {
    ! grep -q 'sources them as before' "$BATS_TEST_DIRNAME/../docs/wrktr.md"
    ! grep -q '^Sources `~/.config/wrktr' "$BATS_TEST_DIRNAME/../docs/wrktr.md"
    ! grep -q 'all variables are unset' "$BATS_TEST_DIRNAME/../docs/wrktr.md"
}

@test "docs: man page does not say a failed wrktr_use unsets all variables" {
    ! grep -q 'all variables are unset' "$BATS_TEST_DIRNAME/../docs/wrktr.1"
}
