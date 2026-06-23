# shellcheck shell=bash
# =============================================================================
# WORKTREE HELPERS (wrktr*) — START
# =============================================================================
#
# Overview
# --------
#
# Requirements
# ------------
#   - bash 3.2 or later (the macOS default is sufficient)
#   - git 2.7 or later; git 2.36+ required for wrktr_init
#   - rsync (required only by wrktr_init)
#
# wrktr is a lightweight shell-based git worktree session manager.
#
# The system is intentionally:
#   - shell-scoped
#   - config-driven
#   - stateless globally
#   - multi-shell safe
#
# Session configs live in:
#
#   ~/.config/wrktr/
#
# Example:
#
#   ~/.config/wrktr/project.env
#
# Example config contents:
#
#   WRKTR_NAME=project
#   WRKTR_BASE_TRUNK=/Users/you/<code_location>
#   WRKTR_BASE_DIR=/Users/you/<code_location>/.wrktr
#   WRKTR_REMOTE=origin
#   WRKTR_MAIN_BRANCH=main
#
# =============================================================================

export WRKTR_VERSION="1.0.1"
export WRKTR_CONFIG_DIR="$HOME/.config/wrktr"
export WRKTR_DRY_RUN=0
export WRKTR_REPO_DIR_NAME="${WRKTR_REPO_DIR_NAME:-.wrktr}"
WRKTR_SOURCE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
export WRKTR_SOURCE_PATH

if ! command -v git >/dev/null 2>&1; then
    printf 'wrktr: required dependency not found: git\n' >&2
fi

function _wrktr_color_index() {
    case "$1" in
        black)   echo 0 ;;
        red)     echo 1 ;;
        green)   echo 2 ;;
        yellow)  echo 3 ;;
        blue)    echo 4 ;;
        magenta) echo 5 ;;
        cyan)    echo 6 ;;
        white)   echo 7 ;;
        *)       return 1 ;;
    esac
}

_wrktr_breaker() {
    local reset color width line out_fd=1

    reset="$(tput sgr0 2>/dev/null || printf '')"
    color="$(tput setaf 2 2>/dev/null || printf '')"
    width="$(tput cols 2>/dev/null || printf '80')"

    case "$1" in
        default)
        color=""
        reset=""
        shift
        ;;
        red)
        color="$(tput setaf "$(_wrktr_color_index "$1")" 2>/dev/null || printf '')"
        out_fd=2
        shift
        ;;
        green|yellow|blue|magenta|cyan|white|black)
        color="$(tput setaf "$(_wrktr_color_index "$1")" 2>/dev/null || printf '')"
        shift
        ;;
    esac

    line="$(printf '%*s' "$width" '' | tr ' ' '-')"

    printf '%s%s%s\n' "$color" "$line" "$reset" >&$out_fd

    if [ "$#" -gt 0 ]; then
        printf '%s%s%s\n' "$color" "$*" "$reset" >&$out_fd
        printf '%s%s%s\n\n' "$color" "$line" "$reset" >&$out_fd
    fi
}

# -----------------------------------------------------------------------------
# _wrktr_is_dryrun
# -----------------------------------------------------------------------------
# What it does:
#   Internal helper used to determine whether wrktr dry-run mode is enabled.
#
# Exit codes:
#   0 — dry-run enabled
#   1 — dry-run disabled
#
# Examples:
#   if _wrktr_is_dryrun; then
#       ...
#   fi
# -----------------------------------------------------------------------------
function _wrktr_is_dryrun() {
    [ "$WRKTR_DRY_RUN" = "1" ]
}

# -----------------------------------------------------------------------------
# _wrktr_run
# -----------------------------------------------------------------------------
# What it does:
#   Internal execution wrapper used for mutating commands.
#
#   When dry-run mode is enabled:
#     - commands are printed
#     - commands are NOT executed
#
#   When dry-run mode is disabled:
#     - commands execute normally
#
# Arguments:
#   All arguments are treated as the command to execute.
#
# Exit codes:
#   Same as underlying command.
#
# Examples:
#   _wrktr_run rm -rf /tmp/test
# -----------------------------------------------------------------------------
function _wrktr_run() {
    if _wrktr_is_dryrun; then
        printf '[DRY RUN] '
        printf '%q ' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

# -----------------------------------------------------------------------------
# _wrktr_assert_subpath
# -----------------------------------------------------------------------------
# What it does:
#   Verifies that a target path resolves to a location inside an expected
#   parent directory. Both paths are resolved to their real absolute forms
#   via pwd -P before comparison, so symlinks cannot be used to escape.
#
# Arguments:
#   $1 — expected parent directory (must exist)
#   $2 — target path to check (parent dir must exist; final component need not)
#
# Exit codes:
#   0 — target is inside parent
#   1 — target is outside parent, or resolution failed
#
# Examples:
#   _wrktr_assert_subpath "$root" "$worktree_dir"
# -----------------------------------------------------------------------------
function _wrktr_assert_subpath() {
    local expected_parent="$1"
    local target="$2"
    local resolved_parent resolved_target target_parent_resolved

    resolved_parent="$(cd "$expected_parent" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Cannot resolve expected parent: $expected_parent"
        return 1
    }

    target_parent_resolved="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Cannot resolve path: $target"
        return 1
    }
    resolved_target="$target_parent_resolved/$(basename "$target")"

    case "$resolved_target" in
        "$resolved_parent"/*|"$resolved_parent")
            return 0
            ;;
        *)
            _wrktr_breaker red "Safety check failed: path is outside expected root"
            _wrktr_breaker red "  Expected root: $resolved_parent"
            _wrktr_breaker red "  Resolved path: $resolved_target"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# _wrktr_confirm_rm
# -----------------------------------------------------------------------------
# What it does:
#   Confirmation wrapper for rm -rf. Resolves the target to its absolute path,
#   displays it, and requires explicit user confirmation before removing.
#
#   If an expected root is provided, the resolved target is verified to be
#   inside that root before prompting. Symlinks are resolved so they cannot
#   be used to escape the expected root.
#
#   In dry-run mode: prints what would be removed without prompting.
#
# Arguments:
#   $1 — path to remove
#   $2 — (optional) expected parent directory; removal is rejected if the
#        resolved target falls outside this path
#
# Exit codes:
#   0 — removed (or dry-run)
#   1 — cancelled, subpath check failed, or resolution failed
#
# Examples:
#   _wrktr_confirm_rm "$worktree_dir" "$root"
# -----------------------------------------------------------------------------
function _wrktr_confirm_rm() {
    local target="$1"
    local expected_root="$2"
    local resolved
    local parent_resolved

    parent_resolved="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)"

    if [ -n "$parent_resolved" ]; then
        resolved="$parent_resolved/$(basename "$target")"
    else
        resolved="$target"
    fi

    if [ -n "$expected_root" ]; then
        _wrktr_assert_subpath "$expected_root" "$resolved" || return 1
    fi

    if _wrktr_is_dryrun; then
        printf '[DRY RUN] rm -rf %q\n' "$resolved"
        return 0
    fi

    _wrktr_breaker yellow "About to permanently remove:"
    printf '  %s\n\n' "$resolved"
    printf 'Confirm removal? [y/N]: '

    local answer
    read -r answer </dev/tty

    case "$answer" in
        y|Y|yes|YES)
            rm -rf "$resolved"
            ;;
        *)
            _wrktr_breaker "Removal cancelled: $resolved"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# _wrktr_git_run
# -----------------------------------------------------------------------------
# What it does:
#   Internal helper used to execute git commands against an explicit git dir
#   while supporting dry-run mode.
#
# Arguments:
#   $1 — git dir
#   Remaining arguments are passed directly to git.
#
# Exit codes:
#   Same as underlying git command.
#
# Examples:
#   _wrktr_git_run ".wrktr" fetch origin
# -----------------------------------------------------------------------------
function _wrktr_git_run() {
    local git_dir="$1"
    shift

    _wrktr_run git --git-dir="$git_dir" "$@"
}


# -----------------------------------------------------------------------------
# wrktr_dryrun_enable
# -----------------------------------------------------------------------------
# What it does:
#   Enables wrktr dry-run mode for the current shell session.
#
# Exit codes:
#   0 — dry-run enabled
#
# Examples:
#   wrktr_dryrun_enable
# -----------------------------------------------------------------------------
function wrktr_dryrun_enable() {
    [ "$1" = "--help" ] && { wrktr_help dryrun_enable; return 0; }
    export WRKTR_DRY_RUN=1
    _wrktr_breaker "wrktr dry-run mode enabled"
}

# -----------------------------------------------------------------------------
# wrktr_dryrun_disable
# -----------------------------------------------------------------------------
# What it does:
#   Disables wrktr dry-run mode for the current shell session.
#
# Exit codes:
#   0 — dry-run disabled
#
# Examples:
#   wrktr_dryrun_disable
# -----------------------------------------------------------------------------
function wrktr_dryrun_disable() {
    [ "$1" = "--help" ] && { wrktr_help dryrun_disable; return 0; }
    export WRKTR_DRY_RUN=0
    _wrktr_breaker "wrktr dry-run mode disabled"
}

# -----------------------------------------------------------------------------
# wrktr_dryrun_status
# -----------------------------------------------------------------------------
# What it does:
#   Displays the current wrktr dry-run status.
#
# Exit codes:
#   0 — status displayed
#
# Examples:
#   wrktr_dryrun_status
# -----------------------------------------------------------------------------
function wrktr_dryrun_status() {
    [ "$1" = "--help" ] && { wrktr_help dryrun_status; return 0; }
    if _wrktr_is_dryrun; then
        _wrktr_breaker "wrktr dry-run mode ENABLED"
    else
        _wrktr_breaker "wrktr dry-run mode DISABLED"
    fi
}


# -----------------------------------------------------------------------------
# wrktr_help
# -----------------------------------------------------------------------------
# What it does:
#   Displays available wrktr commands and a brief explanation of each.
#
# Exit codes:
#   0 — help displayed
#
# Examples:
#   wrktr_help
# -----------------------------------------------------------------------------
function wrktr_help() {
    local cmd="${1:-}"
    cmd="${cmd#wrktr_}"

    case "$cmd" in

    ""|--help)
        cat <<'EOF'
wrktr commands — run 'wrktr_help <command>' for details on any command

Setup (one-time per project)
-----------------------------
wrktr_clone <url> [destination]   Clone an existing remote repo
wrktr_adopt [path]                Convert an existing normal git clone
wrktr_init                        Initialize a new bare repo from local project
wrktr_generate [session]          Create a session config interactively
wrktr_remote_add <name> <url>     Add a remote to the bare repo

Session
-------
wrktr_use <session>               Load a session into the current shell
wrktr_list                        List all available session configs
wrktr_current                     Show the currently-loaded session
wrktr_config_show                 Show the current session config file
wrktr_config_edit                 Edit the current session config in $EDITOR
wrktr_status                      Show all worktrees with branch/ahead/behind/dirty
wrktr_validate                    Validate the loaded session
wrktr_prompt_info                 Prompt string for PS1 embedding

Daily Operations
----------------
wrktr_add <branch> [base-ref]     Create a new branch and worktree, cd into it
wrktr_checkout <branch>           Create a worktree for an existing remote branch
wrktr_go [branch]                 Navigate to a worktree by branch name
wrktr_rebase                      Fetch + rebase current branch onto main
wrktr_push                        Push the current branch (force-with-lease aware)
wrktr_remove <branch>             Remove a worktree and optionally its branch
wrktr_update                      Fetch from the configured remote
wrktr_base                        cd to the trunk directory

Git Access
----------
wrktr_git <args>                  Run git against the bare repo database
wrktr <subcommand>                Raw passthrough to git worktree

Dry Run
-------
wrktr_dryrun_enable               Print commands without executing them
wrktr_dryrun_disable              Disable dry-run mode
wrktr_dryrun_status               Show current dry-run status

Lifecycle
---------
wrktr_unload                      Remove all wrktr functions/vars from this shell
wrktr_reload                      Unload then re-source from original path
EOF
        ;;

    clone)
        cat <<'EOF'
wrktr_clone <url> [destination]

  Clone an existing remote repository into a wrktr bare repository structure
  and create the initial main worktree.

  Arguments:
    url           Remote URL. Handles both HTTPS and SSH URL formats.
    destination   (optional) Local directory to create. Defaults to the repo
                  name derived from the URL in the current directory.

  After cloning, run:
    wrktr_generate
    wrktr_use <session>

  Examples:
    wrktr_clone https://github.com/user/myapp.git
    wrktr_clone git@github.com:user/myapp.git ~/projects/myapp
EOF
        ;;

    adopt)
        cat <<'EOF'
wrktr_adopt [path]

  Convert an existing normal git clone into a wrktr bare repository structure.
  The original clone is not modified — remove it manually when confirmed.

  Prompts:
    Path to existing git clone     Must have a .git subdirectory
    Main branch                    Defaults to the detected HEAD branch
    New trunk directory            Defaults to <parent>/<name>-wrktr
    Main worktree directory        Defaults to 'main'

  After adopting, run:
    wrktr_generate
    wrktr_use <session>

  Examples:
    wrktr_adopt ~/projects/myapp
    wrktr_adopt    (interactive prompts)
EOF
        ;;

    init)
        cat <<'EOF'
wrktr_init

  Initialize a new wrktr-compatible bare repository from an existing local
  project directory. For brand new projects with no remote history.

  Prompts:
    Project root path              Must exist, at least 2 directories deep
    Main worktree directory        Simple name (no /), defaults to 'main'
    Main branch                    Defaults to 'main'

  On failure, a rollback routine runs before removing anything it created.

  After initializing, run:
    wrktr_generate
    wrktr_use <session>

  Examples:
    wrktr_init
EOF
        ;;

    generate)
        cat <<'EOF'
wrktr_generate [session]

  Interactively create a session config and save it to:
    ~/.config/wrktr/<session>.env

  Prompts:
    Session name       Letters, digits, dots, hyphens, underscores only
    Base trunk path    The trunk directory containing the bare repo
    Remote name        Git remote name (e.g. 'origin'). Leave empty for local-only.
    Main branch        Primary integration branch (default: main)

  Examples:
    wrktr_generate
    wrktr_generate myapp
EOF
        ;;

    remote_add)
        cat <<'EOF'
wrktr_remote_add <name> <url>

  Add a remote to the loaded session's bare repository. Also sets the correct
  fetch refspec for bare repositories automatically.

  Use after wrktr_init when you create the remote repository later.

  After adding, update the session config:
    wrktr_config_edit

  Examples:
    wrktr_remote_add origin https://github.com/user/myapp.git
EOF
        ;;

    use)
        cat <<'EOF'
wrktr_use <session>

  Load a project session config into the current shell. Sources
  ~/.config/wrktr/<session>.env and validates the result. If validation
  fails, all variables are unset so the shell is not left in a partial state.

  Examples:
    wrktr_use myapp
EOF
        ;;

    list)
        cat <<'EOF'
wrktr_list

  List all available session configs in ~/.config/wrktr/.
  Does not require a session to be loaded.

  Because error output goes to stderr, this is safe to capture in a script:
    sessions=$(wrktr_list)

  Examples:
    wrktr_list
EOF
        ;;

    current)
        cat <<'EOF'
wrktr_current

  Show the currently-loaded session: name, trunk path, bare database path,
  remote, and main branch.

  Examples:
    wrktr_current
EOF
        ;;

    config_show)
        cat <<'EOF'
wrktr_config_show

  Display the path and full contents of the loaded session's config file.
  Useful for debugging a broken session or confirming stored values.

  Examples:
    wrktr_config_show
EOF
        ;;

    config_edit)
        cat <<'EOF'
wrktr_config_edit

  Open the loaded session's config file in $EDITOR (falls back to vi).
  After the editor closes, validates the config automatically.

  Changes are not applied to the current shell automatically. To pick up
  the new values run: wrktr_use <session>

  Examples:
    wrktr_config_edit
EOF
        ;;

    status)
        cat <<'EOF'
wrktr_status

  Show the status of all active worktrees for the loaded session.
  For each worktree: branch name, commits ahead/behind main, dirty state,
  and full path.

  Examples:
    wrktr_status
EOF
        ;;

    validate)
        cat <<'EOF'
wrktr_validate

  Validate the currently-loaded session. Checks that all required WRKTR_*
  variables are set, the trunk and git directories exist, and the configured
  remote is reachable. Called automatically by most commands.

  Examples:
    wrktr_validate
EOF
        ;;

    prompt_info)
        cat <<'EOF'
wrktr_prompt_info

  Output a short context string for embedding in PS1. Prints nothing when
  no session is loaded, so it is safe to include unconditionally.

  Format:
    [session:branch]   when inside a worktree
    [session]          session loaded, not in a worktree
    (nothing)          no session loaded

  Examples:
    PS1='$(wrktr_prompt_info) \$ '
    PS1='\u@\h $(wrktr_prompt_info)\$ '
EOF
        ;;

    add)
        cat <<'EOF'
wrktr_add <branch> [base-ref]

  Create a new branch and worktree directory, then cd into it.

  Arguments:
    branch      Name for the new branch. Must not already exist locally.
    base-ref    (optional) Ref to branch from. Defaults to origin/<main-branch>
                when a remote is configured, or <main-branch> without one.

  Fetches from the remote automatically before creating (when remote is set).

  Examples:
    wrktr_add feature/login
    wrktr_add fix/crash origin/v2
    wrktr_add experiment/auth main
EOF
        ;;

    checkout)
        cat <<'EOF'
wrktr_checkout <branch>

  Create a local worktree for a branch that already exists on the remote.
  Fetches first, verifies the remote branch exists, creates the worktree,
  sets up upstream tracking, and cds in. Requires a remote to be configured.

  Examples:
    wrktr_checkout feature/login
    wrktr_checkout fix/crash
EOF
        ;;

    go)
        cat <<'EOF'
wrktr_go [branch]

  Navigate into a worktree by branch name. Handles percent-encoding
  automatically — you never need to type the encoded directory name.

  With no argument: shows wrktr_status then prints usage.

  Examples:
    wrktr_go feature/login    # cds to feature%2Flogin/
    wrktr_go main
    wrktr_go                  # show all worktrees
EOF
        ;;

    rebase)
        cat <<'EOF'
wrktr_rebase

  Fetch from the remote and rebase the current branch onto main.
  Must be run from inside a worktree belonging to the loaded session.

  Refuses if:
    - current branch is main
    - working tree has uncommitted changes

  On conflict:
    git add <resolved-files>
    git rebase --continue
    # or: git rebase --abort

  Examples:
    cd ~/<code_location>/feature%2Flogin
    wrktr_rebase
EOF
        ;;

    push)
        cat <<'EOF'
wrktr_push

  Push the current branch to the configured remote.
  Must be run from inside a worktree belonging to the loaded session.

  Refuses to push the main branch. Attempts a regular push first; if rejected
  (expected after wrktr_rebase), prompts before retrying with --force-with-lease.
  Requires a remote to be configured.

  Examples:
    wrktr_push
EOF
        ;;

    remove)
        cat <<'EOF'
wrktr_remove <branch>

  Remove a linked worktree directory, prune its git reference, and
  optionally delete the local branch.

  Refuses if:
    - branch is the main branch
    - worktree has uncommitted changes
    - you are currently inside the worktree (cd out first)

  After removal, prompts whether to delete the local branch ref. If the branch
  has unmerged changes, a second confirmation is required to force-delete.

  Examples:
    wrktr_remove feature/login
EOF
        ;;

    update)
        cat <<'EOF'
wrktr_update

  Fetch all updates from the configured remote. Updates remote tracking refs
  in the bare database without touching any worktree. Silently succeeds with
  no action if no remote is configured.

  Called automatically by wrktr_add, wrktr_rebase, and wrktr_checkout.

  Examples:
    wrktr_update
EOF
        ;;

    base)
        cat <<'EOF'
wrktr_base

  Navigate to the trunk directory — the parent of all worktrees where the
  bare repo database is also visible.

  Examples:
    wrktr_base
EOF
        ;;

    git)
        cat <<'EOF'
wrktr_git <git-args>

  Run any git command against the bare repository by supplying --git-dir
  automatically. Use from outside a worktree. From inside a worktree,
  ordinary 'git' commands work without it.

  Examples:
    wrktr_git fetch origin
    wrktr_git branch -d feature/login
    wrktr_git log --oneline main
    wrktr_git remote -v
EOF
        ;;

    wrktr|passthrough)
        cat <<'EOF'
wrktr <subcommand>

  Raw passthrough to 'git worktree' via the bare repository database.

  Examples:
    wrktr list
    wrktr prune
    wrktr lock feature%2Flogin
EOF
        ;;

    dryrun_enable)
        cat <<'EOF'
wrktr_dryrun_enable

  Enable dry-run mode for the current shell. All mutating commands print
  what they would do without executing anything. Validation still runs.

  Examples:
    wrktr_dryrun_enable
    wrktr_add feature/test    # shows commands, does nothing
    wrktr_dryrun_disable
EOF
        ;;

    dryrun_disable)
        cat <<'EOF'
wrktr_dryrun_disable

  Disable dry-run mode.

  Examples:
    wrktr_dryrun_disable
EOF
        ;;

    dryrun_status)
        cat <<'EOF'
wrktr_dryrun_status

  Show whether dry-run mode is currently enabled or disabled.

  Examples:
    wrktr_dryrun_status
EOF
        ;;

    unload)
        cat <<'EOF'
wrktr_unload

  Remove all wrktr functions and WRKTR_* environment variables from the
  current shell.

  Examples:
    wrktr_unload
EOF
        ;;

    reload)
        cat <<'EOF'
wrktr_reload

  Unload all wrktr functions and re-source worktree-functions.sh from the
  path it was originally loaded from (WRKTR_SOURCE_PATH). Use after editing
  the file to pick up changes without starting a new shell.

  Examples:
    wrktr_reload
EOF
        ;;

    *)
        printf 'wrktr: no help available for "%s"\n' "$1" >&2
        printf 'Run wrktr_help to see all available commands.\n' >&2
        return 1
        ;;

    esac
}

# -----------------------------------------------------------------------------
# wrktr_git
# -----------------------------------------------------------------------------
# What it does:
#   Thin wrapper around:
#
#     git --git-dir="$WRKTR_BASE_DIR"
#
# Arguments:
#   Everything after `wrktr_git` is passed directly to git.
#
# Exit codes:
#   Same as underlying git command.
#
# Examples:
#   wrktr_git fetch origin
#   wrktr_git worktree list
# -----------------------------------------------------------------------------
function wrktr_git() {
    [ "$1" = "--help" ] && { wrktr_help git; return 0; }
    wrktr_validate || return 1

    if _wrktr_is_dryrun; then
        printf '[DRY RUN] '
        printf '%q ' git --git-dir="$WRKTR_BASE_DIR" "$@"
        printf '\n'
        return 0
    fi

    git --git-dir="$WRKTR_BASE_DIR" "$@"
}

# -----------------------------------------------------------------------------
# _wrktr_sanitize_branch_name
# -----------------------------------------------------------------------------
# What it does:
#   Converts a git branch name into a filesystem-safe worktree directory name.
#
#   This prevents branch names containing `/` from creating nested directories.
#
# Arguments:
#   $1 — branch name
#
# Output:
#   Echoes sanitized directory name.
#
# Examples:
#   _wrktr_sanitize_branch_name feature/test
#   # => feature%2Ftest
# -----------------------------------------------------------------------------
function _wrktr_sanitize_branch_name() {
    local branch="$1"

    if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
        return 1
    fi
    echo "${branch//\//%2F}"
}

# -----------------------------------------------------------------------------
# _wrktr_validate_target_dir
# -----------------------------------------------------------------------------
# What it does:
#   Ensures a target worktree directory does not already exist.
#
# Arguments:
#   $1 — target directory path
#
# Exit codes:
#   0 — target safe
#   1 — target already exists
#
# Examples:
#   _wrktr_validate_target_dir "/tmp/test"
# -----------------------------------------------------------------------------
function _wrktr_validate_target_dir() {
    local target="$1"

    if [ -e "$target" ]; then
        _wrktr_breaker red "Target already exists: $target"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# _wrktr_validate_branch_available
# -----------------------------------------------------------------------------
# What it does:
#   Ensures a branch does not already exist locally.
#
# Arguments:
#   $1 — git dir
#   $2 — branch name
#
# Exit codes:
#   0 — branch available
#   1 — branch already exists
#
# Examples:
#   _wrktr_validate_branch_available ".wrktr" "feature/test"
# -----------------------------------------------------------------------------
function _wrktr_validate_branch_available() {
    local git_dir="$1"
    local branch="$2"

    if git --git-dir="$git_dir" show-ref --verify --quiet "refs/heads/$branch"; then
        _wrktr_breaker red "Branch already exists: $branch"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# _wrktr_validate_branch_name
# -----------------------------------------------------------------------------
# What it does:
#   Ensures a branch name is a valid git branch ref.
#
# Arguments:
#   $1 — branch name
#
# Exit codes:
#   0 — branch name valid
#   1 — branch name invalid
#
# Examples:
#   _wrktr_validate_branch_name "feature/test"
# -----------------------------------------------------------------------------
function _wrktr_validate_branch_name() {
    local branch="$1"

    if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
        _wrktr_breaker red "Invalid branch name: $branch"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# _wrktr_create_worktree
# -----------------------------------------------------------------------------
# What it does:
#   Internal helper used to create a git worktree safely.
#
#   This helper is intentionally low-level and does not depend on active
#   wrktr session state.
#
# Arguments:
#   $1 — git dir
#   $2 — base trunk
#   $3 — branch name
#   $4 — base ref
#
# Exit codes:
#   0 — worktree created
#   1 — creation failed
#
# Examples:
#   _wrktr_create_worktree ".wrktr" "/projects/test" "feature/test" "origin/main"
# -----------------------------------------------------------------------------
function _wrktr_create_worktree() {
    local git_dir="$1"
    local trunk="$2"
    local branch="$3"
    local base_ref="$4"
    local target_name="${5:-$branch}"

    local safe_branch
    safe_branch="$(_wrktr_sanitize_branch_name "$target_name")"

    local target="$trunk/$safe_branch"

    _wrktr_validate_target_dir "$target" || return 1
    _wrktr_validate_branch_name "$branch" || return 1
    _wrktr_validate_branch_available "$git_dir" "$branch" || return 1

    _wrktr_breaker "Creating worktree: $target"

    if [ "$base_ref" = "--orphan" ]; then
        if ! _wrktr_git_run "$git_dir" worktree add --orphan -b "$branch" "$target"; then
            _wrktr_breaker red "Failed to create orphan worktree: $target"
            return 1
        fi
    else
        if ! _wrktr_git_run "$git_dir" worktree add "$target" -b "$branch" "$base_ref"; then
            _wrktr_breaker red "Failed to create worktree: $target"
            return 1
        fi
    fi

    _wrktr_breaker "Worktree created successfully: $target"
}

# -----------------------------------------------------------------------------
# wrktr_validate
# -----------------------------------------------------------------------------
# What it does:
#   Validates the currently-loaded wrktr session environment.
#
# Validation checks:
#   - Required WRKTR_* variables exist
#   - Base trunk directory exists
#   - Base git directory exists
#   - Git directory is valid
#   - Configured remote exists
#
# Exit codes:
#   0 — validation successful
#   1 — validation failed
#
# Examples:
#   wrktr_validate
# -----------------------------------------------------------------------------
# shellcheck disable=SC2120
function wrktr_validate() {
    [ "$1" = "--help" ] && { wrktr_help validate; return 0; }
    local missing=0

    if [ -z "$WRKTR_NAME" ] && [ -z "$WRKTR_BASE_DIR" ] && [ -z "$WRKTR_MAIN_BRANCH" ]; then
        _wrktr_breaker red "No session loaded."
        _wrktr_breaker "Use wrktr_list to see available sessions, then: wrktr_use <session-name>"
        return 1
    fi

    [ -z "$WRKTR_NAME" ] && _wrktr_breaker red "WRKTR_NAME is not set" && missing=1
    [ -z "$WRKTR_BASE_TRUNK" ] && _wrktr_breaker red "WRKTR_BASE_TRUNK is not set" && missing=1
    [ -z "$WRKTR_BASE_DIR" ] && _wrktr_breaker red "WRKTR_BASE_DIR is not set" && missing=1
    # [ -z "$WRKTR_REMOTE" ] && _wrktr_breaker red "WRKTR_REMOTE is not set" && missing=1
    [ -z "$WRKTR_MAIN_BRANCH" ] && _wrktr_breaker red "WRKTR_MAIN_BRANCH is not set" && missing=1

    if [ "$missing" -eq 1 ]; then
        return 1
    fi

    if [ ! -d "$WRKTR_BASE_TRUNK" ]; then
        _wrktr_breaker red "WRKTR_BASE_TRUNK does not exist: $WRKTR_BASE_TRUNK"
        return 1
    fi

    if [ ! -d "$WRKTR_BASE_DIR" ]; then
        _wrktr_breaker red "WRKTR_BASE_DIR does not exist: $WRKTR_BASE_DIR"
        return 1
    fi

    if ! git --git-dir="$WRKTR_BASE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        _wrktr_breaker red "Invalid git directory: $WRKTR_BASE_DIR"
        return 1
    fi

    # if ! git --git-dir="$WRKTR_BASE_DIR" remote get-url "$WRKTR_REMOTE" >/dev/null 2>&1; then
    #     _wrktr_breaker red "Remote does not exist: $WRKTR_REMOTE"
    #     return 1
    # fi
    if [ -n "$WRKTR_REMOTE" ]; then
        if ! git --git-dir="$WRKTR_BASE_DIR" remote get-url "$WRKTR_REMOTE" >/dev/null 2>&1; then
            _wrktr_breaker red "Remote does not exist: $WRKTR_REMOTE"
            return 1
        fi
    fi

    return 0
}

# -----------------------------------------------------------------------------
# _wrktr_validate_worktree_context
# -----------------------------------------------------------------------------
# What it does:
#   Verifies that the current working directory is inside a linked worktree
#   that belongs to the loaded wrktr session.
#
#   Two conditions must both be true:
#     - The current directory is inside a git worktree (not a bare repo or a
#       plain directory)
#     - The worktree's git common directory resolves to the same real path as
#       WRKTR_BASE_DIR (symlinks followed via pwd -P)
#
#   This prevents commands that operate on the current branch from running
#   against the wrong session's database, or from running outside any worktree
#   entirely.
#
# Exit codes:
#   0 — current directory is inside a worktree belonging to the session
#   1 — not in a worktree, or worktree belongs to a different session
#
# Examples:
#   _wrktr_validate_worktree_context || return 1
# -----------------------------------------------------------------------------
function _wrktr_validate_worktree_context() {
    local current_common_dir
    local session_common_dir

    current_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        _wrktr_breaker red "Must be run from inside a git worktree"
        return 1
    }

    current_common_dir="$(cd "$current_common_dir" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Could not resolve current git common directory"
        return 1
    }

    session_common_dir="$(cd "$WRKTR_BASE_DIR" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Could not resolve WRKTR_BASE_DIR: $WRKTR_BASE_DIR"
        return 1
    }

    if [ "$current_common_dir" != "$session_common_dir" ]; then
        _wrktr_breaker red "Current directory is not part of the loaded wrktr session"
        _wrktr_breaker red "  Session database: $session_common_dir"
        _wrktr_breaker red "  Current database: $current_common_dir"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# wrktr_list
# -----------------------------------------------------------------------------
# What it does:
#   Lists all available wrktr session configs found in:
#
#     ~/.config/wrktr
#
# Exit codes:
#   0 — list completed
#   1 — config directory missing
#
# Examples:
#   wrktr_list
# -----------------------------------------------------------------------------
function wrktr_list() {
    [ "$1" = "--help" ] && { wrktr_help list; return 0; }
    if [ ! -d "$WRKTR_CONFIG_DIR" ]; then
        _wrktr_breaker red "No session configs found — config directory does not exist: $WRKTR_CONFIG_DIR"
        _wrktr_breaker "Run wrktr_generate to create your first session config."
        return 1
    fi

    _wrktr_breaker "Available wrktr sessions"

    local found=0
    local file

    for file in "$WRKTR_CONFIG_DIR"/*.env; do
        [ -e "$file" ] || continue
        found=1
        basename "$file" .env
    done

    if [ "$found" -eq 0 ]; then
        _wrktr_breaker "No wrktr session configs found."
        _wrktr_breaker "Run wrktr_generate to create your first session config."
    fi
}

# -----------------------------------------------------------------------------
# wrktr_current
# -----------------------------------------------------------------------------
# What it does:
#   Displays information about the currently-loaded wrktr session.
#
# Exit codes:
#   0 — session loaded
#   1 — no session loaded
#
# Examples:
#   wrktr_current
# -----------------------------------------------------------------------------
function wrktr_current() {
    [ "$1" = "--help" ] && { wrktr_help current; return 0; }
    if [ -z "$WRKTR_NAME" ]; then
        _wrktr_breaker red "No wrktr session currently loaded"
        printf 'Use wrktr_list to see available sessions.\n'
        printf 'Then run: wrktr_use <session-name>\n\n'
        return 1
    fi

    if _wrktr_is_dryrun; then
        _wrktr_breaker "Current wrktr session [DRY RUN ENABLED]"
    else
        _wrktr_breaker "Current wrktr session"
    fi

    echo "Name:         $WRKTR_NAME"
    echo "Base trunk:   $WRKTR_BASE_TRUNK"
    echo "Base git dir: $WRKTR_BASE_DIR"
    echo "Remote:       $WRKTR_REMOTE"
    echo "Main branch:  $WRKTR_MAIN_BRANCH"
}

# -----------------------------------------------------------------------------
# wrktr_config_show
# -----------------------------------------------------------------------------
# What it does:
#   Displays the path and contents of the loaded session's config file.
#
#   Useful for debugging a broken session or confirming what values are stored.
#
# Exit codes:
#   0 — config displayed
#   1 — no session loaded or config file missing
#
# Examples:
#   wrktr_config_show
# -----------------------------------------------------------------------------
function wrktr_config_show() {
    [ "$1" = "--help" ] && { wrktr_help config_show; return 0; }
    if [ -z "$WRKTR_NAME" ]; then
        _wrktr_breaker red "No session loaded."
        _wrktr_breaker "Use wrktr_list to see available sessions, then: wrktr_use <session-name>"
        return 1
    fi

    local config="$WRKTR_CONFIG_DIR/$WRKTR_NAME.env"

    _wrktr_breaker "Session config: $config"

    if [ ! -f "$config" ]; then
        _wrktr_breaker red "Config file not found: $config"
        _wrktr_breaker "The session is loaded in this shell but the file no longer exists."
        _wrktr_breaker "Recreate it: wrktr_generate $WRKTR_NAME"
        return 1
    fi

    cat "$config"
}

# -----------------------------------------------------------------------------
# wrktr_config_edit
# -----------------------------------------------------------------------------
# What it does:
#   Opens the loaded session's config file in $EDITOR for manual editing.
#
#   Use this to update a remote URL, rename the main branch, or fix any other
#   stored value without deleting and regenerating the config from scratch.
#
#   After the editor closes, validates the updated config. The edit is
#   preserved even if validation fails — re-run wrktr_config_edit to correct
#   any mistakes.
#
#   Changes are NOT applied to the current shell automatically. To pick up
#   the new values run: wrktr_use <session-name>
#
# Exit codes:
#   0 — editor closed and config is valid
#   1 — no session loaded, config missing, or validation failed after edit
#
# Examples:
#   wrktr_config_edit
# -----------------------------------------------------------------------------
function wrktr_config_edit() {
    [ "$1" = "--help" ] && { wrktr_help config_edit; return 0; }
    if [ -z "$WRKTR_NAME" ]; then
        _wrktr_breaker red "No session loaded."
        _wrktr_breaker "Use wrktr_list to see available sessions, then: wrktr_use <session-name>"
        return 1
    fi

    local config="$WRKTR_CONFIG_DIR/$WRKTR_NAME.env"

    if [ ! -f "$config" ]; then
        _wrktr_breaker red "Config file not found: $config"
        _wrktr_breaker "Recreate it: wrktr_generate $WRKTR_NAME"
        return 1
    fi

    "${EDITOR:-vi}" "$config"

    _wrktr_breaker "Validating updated config..."
    if ! wrktr_validate; then
        _wrktr_breaker red "Config has errors. Fix with: wrktr_config_edit"
        return 1
    fi

    _wrktr_breaker "Config is valid."
    printf 'To apply changes in this shell: wrktr_use %s\n\n' "$WRKTR_NAME"
}

# -----------------------------------------------------------------------------
# wrktr_prompt_info
# -----------------------------------------------------------------------------
# What it does:
#   Outputs a short string describing the current wrktr context, suitable for
#   embedding in a shell prompt.
#
#   Prints nothing and exits 0 if no session is loaded, so it is safe to
#   include in PS1 unconditionally.
#
#   Format: [session:branch]  or  [session]  when not inside a worktree.
#
# Exit codes:
#   0 — always
#
# Examples:
#   PS1='$(wrktr_prompt_info) \$ '
#   PS1='\u@\h $(wrktr_prompt_info)\$ '
# -----------------------------------------------------------------------------
function wrktr_prompt_info() {
    [ "$1" = "--help" ] && { wrktr_help prompt_info; return 0; }
    [ -z "$WRKTR_NAME" ] && return 0

    local branch
    branch="$(git branch --show-current 2>/dev/null)"

    if [ -n "$branch" ]; then
        printf '[%s:%s]' "$WRKTR_NAME" "$branch"
    else
        printf '[%s]' "$WRKTR_NAME"
    fi
}

# -----------------------------------------------------------------------------
# _wrktr_status_print_entry
# -----------------------------------------------------------------------------
# Internal helper for wrktr_status. Prints status for one worktree entry.
# -----------------------------------------------------------------------------
function _wrktr_status_print_entry() {
    local path="$1"
    local branch="$2"
    local compare_ref="$3"

    if [ ! -d "$path" ]; then
        printf '  %-40s  [directory missing]\n\n' "${branch:-detached}"
        return
    fi

    local dirty=""
    if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
        dirty="  [dirty]"
    fi

    local ahead=0
    local behind=0
    if git --git-dir="$WRKTR_BASE_DIR" rev-parse --verify "$compare_ref" >/dev/null 2>&1; then
        ahead=$(git --git-dir="$WRKTR_BASE_DIR" rev-list --count "${compare_ref}..${branch}" 2>/dev/null || printf '0')
        behind=$(git --git-dir="$WRKTR_BASE_DIR" rev-list --count "${branch}..${compare_ref}" 2>/dev/null || printf '0')
    fi

    local ab=""
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
        ab="  (+${ahead}/-${behind} vs ${compare_ref})"
    elif [ "$ahead" -gt 0 ]; then
        ab="  (+${ahead} ahead of ${compare_ref})"
    elif [ "$behind" -gt 0 ]; then
        ab="  (-${behind} behind ${compare_ref})"
    fi

    printf '  branch: %s%s%s\n  path:   %s\n\n' \
        "${branch:-detached}" "$ab" "$dirty" "$path"
}

# -----------------------------------------------------------------------------
# wrktr_status
# -----------------------------------------------------------------------------
# What it does:
#   Shows the status of all active worktrees for the loaded session.
#
#   For each worktree, displays:
#     - Branch name
#     - Commits ahead of or behind the main branch
#     - Whether the working tree has uncommitted changes
#     - Full directory path
#
# Exit codes:
#   0 — status displayed
#   1 — validation failed
#
# Examples:
#   wrktr_status
# -----------------------------------------------------------------------------
# shellcheck disable=SC2120
function wrktr_status() {
    [ "$1" = "--help" ] && { wrktr_help status; return 0; }
    wrktr_validate || return 1

    local compare_ref
    if [ -n "$WRKTR_REMOTE" ]; then
        compare_ref="$WRKTR_REMOTE/$WRKTR_MAIN_BRANCH"
    else
        compare_ref="$WRKTR_MAIN_BRANCH"
    fi

    _wrktr_breaker "Worktree status for $WRKTR_NAME (vs $compare_ref)"

    local wt_path=""
    local wt_branch=""
    local wt_is_bare=0

    while IFS= read -r wt_line; do
        case "$wt_line" in
            "worktree "*)
                if [ -n "$wt_path" ] && [ "$wt_is_bare" -eq 0 ]; then
                    _wrktr_status_print_entry "$wt_path" "$wt_branch" "$compare_ref"
                fi
                wt_path="${wt_line#worktree }"
                wt_branch=""
                wt_is_bare=0
                ;;
            "bare")
                wt_is_bare=1
                ;;
            "branch "*)
                wt_branch="${wt_line#branch refs/heads/}"
                ;;
        esac
    done < <(git --git-dir="$WRKTR_BASE_DIR" worktree list --porcelain 2>/dev/null)

    if [ -n "$wt_path" ] && [ "$wt_is_bare" -eq 0 ]; then
        _wrktr_status_print_entry "$wt_path" "$wt_branch" "$compare_ref"
    fi
}

# -----------------------------------------------------------------------------
# wrktr_use
# -----------------------------------------------------------------------------
# What it does:
#   Loads a wrktr session config into the current shell environment.
#
# Arguments:
#   $1 — session name
#
# Exit codes:
#   0 — session loaded successfully
#   1 — session missing or validation failed
#
# Examples:
#   wrktr_use project
# -----------------------------------------------------------------------------
function wrktr_use() {
    [ "$1" = "--help" ] && { wrktr_help use; return 0; }
    if [ -z "$1" ]; then
        _wrktr_breaker red "Usage: wrktr_use <session>"
        return 1
    fi

    local session="$1"

    if [[ ! "$session" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        _wrktr_breaker red "Invalid session name: $session"
        return 1
    fi

    local config="$WRKTR_CONFIG_DIR/$session.env"

    if [ ! -f "$config" ]; then
        _wrktr_breaker red "wrktr session does not exist: $session"
        _wrktr_breaker "Use 'wrktr_list' to see available sessions."
        _wrktr_breaker "To create a new config: wrktr_generate $session"
        return 1
    fi

    if grep -q '^export WRKTR_' "$config" 2>/dev/null; then
        printf 'wrktr: session "%s" uses the old config format (has "export " prefix).\n' "$session" >&2
        printf 'To migrate: wrktr_config_edit — remove "export " from each line.\n\n' >&2
    fi

    local _line _key _value
    while IFS= read -r _line; do
        case "$_line" in
            ''|'#'*) continue ;;
        esac
        _key="${_line%%=*}"
        _key="${_key#export }"
        _value="${_line#*=}"
        case "$_key" in
            WRKTR_*) export "$_key"="$_value" ;;
        esac
    done < "$config"

    if ! wrktr_validate; then
        _wrktr_breaker red "wrktr session validation failed: $session"
        printf '\nPossible causes:\n'
        printf '  - The project directory was moved or deleted\n'
        printf '  - The %s directory is missing (re-run wrktr_init)\n' "$WRKTR_REPO_DIR_NAME"
        printf '  - The configured remote no longer exists\n'
        printf '\nTo recreate the config: wrktr_generate %s\n\n' "$session"

        unset WRKTR_NAME
        unset WRKTR_BASE_TRUNK
        unset WRKTR_BASE_DIR
        unset WRKTR_REMOTE
        unset WRKTR_MAIN_BRANCH

        return 1
    fi

    _wrktr_breaker "Loaded wrktr session: $WRKTR_NAME"
}

# -----------------------------------------------------------------------------
# wrktr_generate
# -----------------------------------------------------------------------------
# What it does:
#   Interactively creates a new wrktr session config.
#
#   When dry-run mode is enabled:
#     - validation still occurs
#     - the generated config contents are printed
#     - no files are written
#
# Arguments:
#   $1 — optional session name
#
# Exit codes:
#   0 — config created successfully
#   1 — validation failed or config already exists
#
# Examples:
#   wrktr_generate
#   wrktr_generate project
# -----------------------------------------------------------------------------
function wrktr_generate() {
    [ "$1" = "--help" ] && { wrktr_help generate; return 0; }
    local session="$1"

    if [ -z "$session" ] && [ ! -t 0 ]; then
        _wrktr_breaker red "wrktr_generate requires an interactive terminal when no session name is given"
        return 1
    fi

    if [ -z "$session" ]; then
        # read -r -p "Session name: " session
        printf "Session name: "
        read -r session
    fi

    if [ -z "$session" ]; then
        _wrktr_breaker red "Session name cannot be empty"
        return 1
    fi

    if [[ ! "$session" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        _wrktr_breaker red "Invalid session name: $session"
        _wrktr_breaker "Use only letters, digits, dots, hyphens, and underscores"
        return 1
    fi

    local config="$WRKTR_CONFIG_DIR/$session.env"

    if [ -f "$config" ]; then
        _wrktr_breaker red "Session config already exists: $config"
        _wrktr_breaker "To load it: wrktr_use $session"
        return 1
    fi

    local trunk
    local remote
    local main_branch

    printf "Base trunk path: "
    read -r trunk

    if [ -z "$trunk" ]; then
        _wrktr_breaker red "Base trunk path cannot be empty"
        return 1
    fi

    printf "Remote name (leave empty for none): "
    read -r remote

    printf "Main branch [main]: "
    read -r main_branch

    # remote="${remote:-origin}"
    main_branch="${main_branch:-main}"

    if [ ! -d "$trunk" ]; then
        _wrktr_breaker red "Base trunk path does not exist: $trunk"
        return 1
    fi

    trunk="$(cd "$trunk" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Cannot resolve trunk path to absolute path"
        return 1
    }

    local git_dir="$trunk/$WRKTR_REPO_DIR_NAME"

    if [ ! -d "$git_dir" ]; then
        _wrktr_breaker red "Git directory does not exist: $git_dir"
        _wrktr_breaker "Has this project been initialized? Run: wrktr_init"
        return 1
    fi

    if ! git --git-dir="$git_dir" rev-parse --git-dir >/dev/null 2>&1; then
        _wrktr_breaker red "Invalid git directory: $git_dir"
        return 1
    fi

    # if ! git --git-dir="$git_dir" remote get-url "$remote" >/dev/null 2>&1; then
    #     _wrktr_breaker red "Remote does not exist: $remote"
    #     return 1
    # fi

    if [ -n "$remote" ]; then
        if ! git --git-dir="$git_dir" remote get-url "$remote" >/dev/null 2>&1; then
            _wrktr_breaker red "Remote does not exist: $remote"
            return 1
        fi
    fi

    if _wrktr_is_dryrun; then
        _wrktr_breaker "[DRY RUN] Would create config: $config"
        printf 'WRKTR_NAME=%s\n' "$session"
        printf 'WRKTR_BASE_TRUNK=%s\n' "$trunk"
        printf 'WRKTR_BASE_DIR=%s\n' "$git_dir"
        printf 'WRKTR_REMOTE=%s\n' "$remote"
        printf 'WRKTR_MAIN_BRANCH=%s\n' "$main_branch"
        printf '\n'
        return 0
    fi

    mkdir -p "$WRKTR_CONFIG_DIR" || {
        _wrktr_breaker red "Failed to create config directory"
        return 1
    }

    local tmp
    tmp="$(mktemp)" || {
        _wrktr_breaker red "Failed to create temp file"
        return 1
    }

    {
        printf '# wrktr session config\n'
        printf 'WRKTR_NAME=%s\n' "$session"
        printf 'WRKTR_BASE_TRUNK=%s\n' "$trunk"
        printf 'WRKTR_BASE_DIR=%s\n' "$git_dir"
        printf 'WRKTR_REMOTE=%s\n' "$remote"
        printf 'WRKTR_MAIN_BRANCH=%s\n' "$main_branch"
    } > "$tmp"

    mv "$tmp" "$config" || {
        _wrktr_breaker red "Failed to write config file"
        rm -f "$tmp"
        return 1
    }

    _wrktr_breaker "wrktr session created successfully: $session"
    printf '\nNext steps:\n'
    printf '  1. Load the session:       wrktr_use %s\n' "$session"
    printf '  2. Start a feature branch: wrktr_add <branch-name>\n\n'
}

# -----------------------------------------------------------------------------
# wrktr_init
# -----------------------------------------------------------------------------
# What it does:
#   Initializes a new wrktr-compatible repository structure.
#
#   This function is intended ONLY for initializing new repositories and
#   intentionally refuses to operate on existing git repositories or worktrees.
#
#   The initialization flow:
#     - creates a shared bare git directory (.wrktr)
#     - creates the initial/main worktree
#     - creates the initial branch
#     - optionally creates an initial commit
#
#   This function intentionally does NOT:
#     - create feature worktrees
#     - create remotes
#     - generate session configs
#
# Exit codes:
#   0 — initialization successful
#   1 — initialization failed
#
# Examples:
#   wrktr_init
# -----------------------------------------------------------------------------
function wrktr_init() {
    [ "$1" = "--help" ] && { wrktr_help init; return 0; }
    if [ ! -t 0 ]; then
        _wrktr_breaker red "wrktr_init requires an interactive terminal"
        return 1
    fi
    if ! command -v rsync >/dev/null 2>&1; then
        _wrktr_breaker red "rsync is required by wrktr_init but was not found"
        return 1
    fi

    local root
    local main_worktree
    local main_branch

    printf "Project root path: "
    read -r root

    if [ -z "$root" ]; then
        _wrktr_breaker red "Project root path cannot be empty"
        return 1
    fi

    printf "Main worktree directory [main]: "
    read -r main_worktree

    printf "Main branch [main]: "
    read -r main_branch

    main_worktree="${main_worktree:-main}"
    main_branch="${main_branch:-main}"

    if [[ "$main_worktree" == */* ]] || [[ "$main_worktree" == "." ]] || [[ "$main_worktree" == ".." ]]; then
        _wrktr_breaker red "Invalid worktree directory name: $main_worktree"
        return 1
    fi

    if [ ! -d "$root" ]; then
        _wrktr_breaker red "Project root does not exist: $root"
        return 1
    fi

    local abs_root
    abs_root="$(cd "$root" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Cannot resolve project root to absolute path: $root"
        return 1
    }
    local _wrktr_init_depth
    _wrktr_init_depth=$(printf '%s' "$abs_root" | tr -cd '/' | wc -c | tr -d ' ')
    if [ "$_wrktr_init_depth" -lt 2 ]; then
        _wrktr_breaker red "Project root is too shallow; must be at least 2 levels deep: $abs_root"
        return 1
    fi

    local repo_dir="$abs_root/$WRKTR_REPO_DIR_NAME"
    local worktree_dir="$abs_root/$main_worktree"

    if [ -d "$repo_dir" ]; then
        _wrktr_breaker red "Repository already initialized: $repo_dir"
        return 1
    fi

    if [ -e "$worktree_dir/.git" ]; then
        _wrktr_breaker red "Directory already appears to be part of a git repository:"
        _wrktr_breaker red "$worktree_dir"
        return 1
    fi

    if [ ! -d "$worktree_dir" ]; then
        _wrktr_breaker red "Main worktree directory does not exist: $worktree_dir"
        return 1
    fi

    _wrktr_breaker "Initializing bare repository"

    if ! _wrktr_run git init --bare "$repo_dir"; then
        _wrktr_breaker red "Failed to initialize bare repository"
        return 1
    fi

    local tmp_dir="$abs_root/.wrktr-init-tmp"
    local init_success=0

    if [ -e "$tmp_dir" ]; then
        _wrktr_breaker red "Temporary initialization directory already exists:"
        _wrktr_breaker red "$tmp_dir"
        return 1
    fi

    # shellcheck disable=SC2317,SC2329
    function _wrktr_init_cleanup() {
        if [ "$init_success" -eq 1 ] || _wrktr_is_dryrun; then
            unset -f _wrktr_init_cleanup
            return 0
        fi

        if [ -d "$tmp_dir" ]; then
            _wrktr_breaker "Cleaning up partial initialization state"

            if [ -e "$worktree_dir" ]; then
                _wrktr_confirm_rm "$worktree_dir" "$abs_root"
            fi

            _wrktr_run mv "$tmp_dir" "$worktree_dir"
        fi

        if [ -d "$repo_dir" ]; then
            _wrktr_confirm_rm "$repo_dir" "$abs_root"
        fi

        unset -f _wrktr_init_cleanup
    }

    trap _wrktr_init_cleanup RETURN

    _wrktr_breaker "Temporarily relocating existing worktree contents"

    if ! _wrktr_run mv "$worktree_dir" "$tmp_dir"; then
        _wrktr_breaker red "Failed to relocate existing worktree directory"
        return 1
    fi

    if ! _wrktr_create_worktree \
        "$repo_dir" \
        "$abs_root" \
        "$main_branch" \
        "--orphan" \
        "$main_worktree"; then

        return 1
    fi

    _wrktr_breaker "Restoring original project files"

    if ! _wrktr_run rsync -a "$tmp_dir"/ "$worktree_dir"/; then
        _wrktr_breaker red "Failed to restore project files"

        _wrktr_confirm_rm "$worktree_dir" "$abs_root"
        _wrktr_run mv "$tmp_dir" "$worktree_dir"

        return 1
    fi

    _wrktr_confirm_rm "$tmp_dir" "$abs_root"
    tmp_dir=""

    if ! _wrktr_is_dryrun; then
        (
            cd "$worktree_dir" || exit 1

            git add . || exit 1

            if ! git diff --cached --quiet; then
                git commit -m "Initial commit" || exit 1
            fi
        ) || {
            _wrktr_breaker red "Failed to finalize initial repository state"
            return 1
        }
    else
        _wrktr_breaker "[DRY RUN] Would initialize orphan branch: $main_branch"
        _wrktr_breaker "[DRY RUN] Would create initial commit"
    fi

    init_success=1
    trap - RETURN
    unset -f _wrktr_init_cleanup

    if _wrktr_is_dryrun; then
        _wrktr_breaker "[DRY RUN] wrktr repository initialization simulation complete"
    else
        _wrktr_breaker "wrktr repository initialized successfully"
        printf '\nNext steps:\n'
        printf '  1. Create a session config:  wrktr_generate\n'
        printf '  2. Load the session:         wrktr_use <session-name>\n'
        printf '  3. Start a feature branch:   wrktr_add <branch-name>\n\n'
    fi
}

# -----------------------------------------------------------------------------
# wrktr_clone
# -----------------------------------------------------------------------------
# What it does:
#   Clones an existing remote repository into a wrktr-compatible bare
#   repository structure and creates the initial main worktree.
#
#   This is the entry point for adopting an existing remote project into the
#   wrktr workflow. Use wrktr_init instead when starting a brand new local
#   project with no remote history.
#
#   After cloning, run wrktr_generate to create a session config.
#
# Arguments:
#   $1 — remote URL to clone
#   $2 — (optional) local destination directory; defaults to the repository
#        name derived from the URL in the current directory
#
# Exit codes:
#   0 — clone succeeded
#   1 — clone failed
#
# Examples:
#   wrktr_clone https://github.com/user/myapp.git
#   wrktr_clone https://github.com/user/myapp.git ~/projects/myapp
# -----------------------------------------------------------------------------
function wrktr_clone() {
    [ "$1" = "--help" ] && { wrktr_help clone; return 0; }
    if [ -z "$1" ]; then
        _wrktr_breaker red "Usage: wrktr_clone <url> [destination]"
        return 1
    fi

    local url="$1"
    local destination="${2:-}"

    if [ -z "$destination" ]; then
        # Strip up to last / or : to handle both HTTPS and SSH URLs
        # https://github.com/user/repo.git  →  repo
        # git@github.com:user/repo.git      →  repo
        local repo_name
        repo_name="${url##*[/:]}"
        repo_name="${repo_name%.git}"
        if [ -z "$repo_name" ] || [ "$repo_name" = "." ]; then
            _wrktr_breaker red "Cannot derive destination name from URL: $url"
            _wrktr_breaker "Provide a destination: wrktr_clone <url> <path>"
            return 1
        fi
        destination="$repo_name"
    fi

    local dest_name dest_parent resolved_parent abs_destination
    dest_name="$(basename "$destination")"
    dest_parent="$(dirname "$destination")"

    resolved_parent="$(cd "$dest_parent" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Parent directory does not exist: $dest_parent"
        return 1
    }
    abs_destination="$resolved_parent/$dest_name"

    local depth
    depth=$(printf '%s' "$abs_destination" | tr -cd '/' | wc -c | tr -d ' ')
    if [ "$depth" -lt 2 ]; then
        _wrktr_breaker red "Destination is too shallow; must be at least 2 levels deep: $abs_destination"
        return 1
    fi

    if [ -e "$abs_destination" ]; then
        _wrktr_breaker red "Destination already exists: $abs_destination"
        return 1
    fi

    local repo_dir="$abs_destination/$WRKTR_REPO_DIR_NAME"
    local worktree_dir="$abs_destination/main"

    if _wrktr_is_dryrun; then
        _wrktr_breaker "[DRY RUN] Would clone $url into $abs_destination"
        printf '[DRY RUN] mkdir %q\n' "$abs_destination"
        printf '[DRY RUN] git clone --bare %q %q\n' "$url" "$repo_dir"
        printf '[DRY RUN] git worktree add %q <main-branch>\n' "$worktree_dir"
        printf '\nNext steps after cloning:\n'
        printf '  1. Create a session config:  wrktr_generate\n'
        printf '     (trunk path: %s)\n' "$abs_destination"
        printf '  2. Load the session:         wrktr_use <session-name>\n'
        printf '  3. Start a feature branch:   wrktr_add <branch-name>\n\n'
        return 0
    fi

    _wrktr_breaker "Cloning $url"

    mkdir "$abs_destination" || {
        _wrktr_breaker red "Failed to create destination directory: $abs_destination"
        return 1
    }

    if ! git clone --bare "$url" "$repo_dir"; then
        _wrktr_breaker red "Clone failed"
        _wrktr_breaker "Cleaning up: $abs_destination"
        rm -rf "$abs_destination"
        return 1
    fi

    # Bare clones don't set up refs/remotes/origin/* by default.
    # Fix the fetch refspec so wrktr_add can use origin/main as a base ref.
    git --git-dir="$repo_dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

    _wrktr_breaker "Fetching remote refs..."
    if ! git --git-dir="$repo_dir" fetch origin; then
        _wrktr_breaker yellow "Fetch warning: remote tracking refs may be incomplete"
    fi

    local main_branch
    main_branch="$(git --git-dir="$repo_dir" symbolic-ref --short HEAD 2>/dev/null)"

    if [ -z "$main_branch" ]; then
        if git --git-dir="$repo_dir" show-ref --verify --quiet refs/heads/main; then
            main_branch="main"
        elif git --git-dir="$repo_dir" show-ref --verify --quiet refs/heads/master; then
            main_branch="master"
        else
            main_branch="$(git --git-dir="$repo_dir" branch 2>/dev/null | head -1 | tr -d '* ')"
        fi
    fi

    if [ -z "$main_branch" ]; then
        _wrktr_breaker yellow "Repository appears to be empty (no commits yet)"
        _wrktr_breaker "Bare repository cloned to: $repo_dir"
        printf '\nAfter pushing initial commits, create the main worktree:\n'
        printf '  git --git-dir=%s worktree add %s <branch>\n\n' "$repo_dir" "$worktree_dir"
        printf 'Then create a session config:\n'
        printf '  wrktr_generate\n\n'
        return 0
    fi

    worktree_dir="$abs_destination/$(_wrktr_sanitize_branch_name "$main_branch")"

    _wrktr_breaker "Detected main branch: $main_branch"
    _wrktr_breaker "Creating main worktree: $worktree_dir"

    if ! git --git-dir="$repo_dir" worktree add "$worktree_dir" "$main_branch"; then
        _wrktr_breaker red "Failed to create main worktree"
        _wrktr_breaker "The bare repository is at: $repo_dir"
        printf '\nCreate the worktree manually:\n'
        printf '  git --git-dir=%s worktree add %s %s\n\n' "$repo_dir" "$worktree_dir" "$main_branch"
        return 1
    fi

    local suggested_session
    suggested_session="$(basename "$abs_destination")"

    _wrktr_breaker "Clone complete"
    printf '\nCloned to:     %s\n' "$abs_destination"
    printf 'Main branch:   %s\n' "$main_branch"
    printf 'Main worktree: %s\n\n' "$worktree_dir"
    printf 'Next steps:\n'
    printf '  1. wrktr_generate\n'
    printf '     When prompted:\n'
    printf '       Session name:    %s\n' "$suggested_session"
    printf '       Base trunk path: %s\n' "$abs_destination"
    printf '       Remote:          origin\n'
    printf '       Main branch:     %s\n\n' "$main_branch"
    printf '  2. wrktr_use %s\n\n' "$suggested_session"
    printf '  3. wrktr_add <branch-name>\n\n'
}

# -----------------------------------------------------------------------------
# wrktr_adopt
# -----------------------------------------------------------------------------
# What it does:
#   Converts an existing normal git clone into a wrktr-compatible bare
#   repository structure.
#
#   Use this when you already have a local clone and want to start using the
#   wrktr workflow without re-cloning from a remote. wrktr_adopt creates a
#   new bare repo from the existing clone, creates the main worktree, and
#   restores any remote the original clone had.
#
#   The original clone is not modified or deleted — you can remove it manually
#   after confirming the new structure works.
#
# Arguments:
#   $1 — (optional) path to the existing git clone
#
# Exit codes:
#   0 — adoption succeeded
#   1 — adoption failed
#
# Examples:
#   wrktr_adopt
#   wrktr_adopt ~/projects/myapp
# -----------------------------------------------------------------------------
function wrktr_adopt() {
    [ "$1" = "--help" ] && { wrktr_help adopt; return 0; }
    if [ ! -t 0 ]; then
        _wrktr_breaker red "wrktr_adopt requires an interactive terminal"
        return 1
    fi
    local existing_path="${1:-}"

    if [ -z "$existing_path" ]; then
        printf "Path to existing git clone: "
        read -r existing_path
    fi

    if [ -z "$existing_path" ]; then
        _wrktr_breaker red "Path cannot be empty"
        return 1
    fi

    local abs_existing
    abs_existing="$(cd "$existing_path" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Path does not exist: $existing_path"
        return 1
    }

    if [ ! -d "$abs_existing/.git" ]; then
        _wrktr_breaker red "Not a normal git clone: $abs_existing"
        _wrktr_breaker "Expected a directory with a .git subdirectory."
        _wrktr_breaker "For bare repos, use wrktr_generate to create a session config directly."
        return 1
    fi

    local main_branch
    main_branch="$(git -C "$abs_existing" branch --show-current 2>/dev/null)"
    if [ -z "$main_branch" ]; then
        main_branch="$(git -C "$abs_existing" symbolic-ref --short HEAD 2>/dev/null)"
    fi
    [ -z "$main_branch" ] && main_branch="main"

    printf "Main branch [%s]: " "$main_branch"
    read -r input_branch
    main_branch="${input_branch:-$main_branch}"

    local suggested_trunk
    suggested_trunk="$(dirname "$abs_existing")/$(basename "$abs_existing")-wrktr"
    printf "New trunk directory [%s]: " "$suggested_trunk"
    local trunk_path
    read -r trunk_path
    trunk_path="${trunk_path:-$suggested_trunk}"

    if [ -z "$trunk_path" ]; then
        _wrktr_breaker red "Trunk path cannot be empty"
        return 1
    fi

    local trunk_name trunk_parent resolved_trunk_parent abs_trunk
    trunk_name="$(basename "$trunk_path")"
    trunk_parent="$(dirname "$trunk_path")"
    resolved_trunk_parent="$(cd "$trunk_parent" 2>/dev/null && pwd -P)" || {
        _wrktr_breaker red "Parent directory does not exist: $trunk_parent"
        return 1
    }
    abs_trunk="$resolved_trunk_parent/$trunk_name"

    local depth
    depth=$(printf '%s' "$abs_trunk" | tr -cd '/' | wc -c | tr -d ' ')
    if [ "$depth" -lt 2 ]; then
        _wrktr_breaker red "Trunk is too shallow; must be at least 2 levels deep: $abs_trunk"
        return 1
    fi

    if [ -e "$abs_trunk" ]; then
        _wrktr_breaker red "Trunk directory already exists: $abs_trunk"
        return 1
    fi

    printf "Main worktree directory [main]: "
    local main_worktree_name
    read -r main_worktree_name
    main_worktree_name="${main_worktree_name:-main}"

    if [[ "$main_worktree_name" == */* ]] || [[ "$main_worktree_name" == "." ]] || [[ "$main_worktree_name" == ".." ]]; then
        _wrktr_breaker red "Invalid worktree directory name: $main_worktree_name"
        return 1
    fi

    local original_remote_url
    original_remote_url="$(git -C "$abs_existing" remote get-url origin 2>/dev/null || true)"

    local repo_dir="$abs_trunk/$WRKTR_REPO_DIR_NAME"
    local worktree_dir="$abs_trunk/$main_worktree_name"

    if _wrktr_is_dryrun; then
        _wrktr_breaker "[DRY RUN] Would adopt $abs_existing"
        printf '[DRY RUN] mkdir %q\n' "$abs_trunk"
        printf '[DRY RUN] git clone --bare %q %q\n' "$abs_existing" "$repo_dir"
        printf '[DRY RUN] git --git-dir=%q worktree add %q %q\n' "$repo_dir" "$worktree_dir" "$main_branch"
        if [ -n "$original_remote_url" ]; then
            printf '[DRY RUN] Restore remote origin: %s\n' "$original_remote_url"
        fi
        return 0
    fi

    _wrktr_breaker "Adopting $abs_existing"

    mkdir "$abs_trunk" || {
        _wrktr_breaker red "Failed to create trunk directory: $abs_trunk"
        return 1
    }

    _wrktr_breaker "Creating bare clone..."
    if ! git clone --bare "$abs_existing" "$repo_dir"; then
        _wrktr_breaker red "Failed to create bare clone"
        _wrktr_breaker "Cleaning up: $abs_trunk"
        rm -rf "$abs_trunk"
        return 1
    fi

    # The local clone becomes "origin" from the bare clone's perspective — remove
    # that and restore the actual upstream remote if the original had one.
    git --git-dir="$repo_dir" remote remove origin 2>/dev/null || true

    if [ -n "$original_remote_url" ]; then
        git --git-dir="$repo_dir" remote add origin "$original_remote_url"
        git --git-dir="$repo_dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
        _wrktr_breaker "Restored remote: origin → $original_remote_url"
    fi

    _wrktr_breaker "Creating main worktree: $worktree_dir"
    if ! git --git-dir="$repo_dir" worktree add "$worktree_dir" "$main_branch"; then
        _wrktr_breaker red "Failed to create main worktree"
        _wrktr_breaker "Cleaning up: $abs_trunk"
        rm -rf "$abs_trunk"
        return 1
    fi

    local suggested_session
    suggested_session="$(basename "$abs_trunk")"

    _wrktr_breaker "Adoption complete"
    printf '\nNew trunk:     %s\n' "$abs_trunk"
    printf 'Main worktree: %s\n' "$worktree_dir"
    printf 'Main branch:   %s\n' "$main_branch"
    [ -n "$original_remote_url" ] && printf 'Remote origin: %s\n' "$original_remote_url"
    printf '\nThe original clone is unchanged and can be removed when ready:\n'
    printf '  rm -rf %s\n\n' "$abs_existing"
    printf 'Next steps:\n'
    printf '  1. wrktr_generate\n'
    printf '     When prompted:\n'
    printf '       Session name:    %s\n' "$suggested_session"
    printf '       Base trunk path: %s\n' "$abs_trunk"
    if [ -n "$original_remote_url" ]; then
        printf '       Remote:          origin\n'
    else
        printf '       Remote:          (leave empty)\n'
    fi
    printf '       Main branch:     %s\n\n' "$main_branch"
    printf '  2. wrktr_use %s\n\n' "$suggested_session"
}

# -----------------------------------------------------------------------------
# wrktr_remote_add
# -----------------------------------------------------------------------------
# What it does:
#   Adds a remote to the loaded session's bare repository.
#
#   Use this when you initialized locally with wrktr_init and later need to
#   connect to a remote (e.g. after creating a GitHub repository).
#
#   After adding a remote, update your session config to reference it:
#     rm ~/.config/wrktr/<session>.env
#     wrktr_generate <session>
#
# Arguments:
#   $1 — remote name (e.g. origin)
#   $2 — remote URL
#
# Exit codes:
#   0 — remote added
#   1 — validation or add failed
#
# Examples:
#   wrktr_remote_add origin https://github.com/user/myapp.git
# -----------------------------------------------------------------------------
function wrktr_remote_add() {
    [ "$1" = "--help" ] && { wrktr_help remote_add; return 0; }
    wrktr_validate || return 1

    if [ -z "$1" ] || [ -z "$2" ]; then
        _wrktr_breaker red "Usage: wrktr_remote_add <name> <url>"
        return 1
    fi

    local name="$1"
    local url="$2"

    if git --git-dir="$WRKTR_BASE_DIR" remote get-url "$name" >/dev/null 2>&1; then
        local existing_url
        existing_url="$(git --git-dir="$WRKTR_BASE_DIR" remote get-url "$name")"
        _wrktr_breaker red "Remote already exists: $name"
        printf '  Current URL: %s\n\n' "$existing_url"
        return 1
    fi

    if ! wrktr_git remote add "$name" "$url"; then
        _wrktr_breaker red "Failed to add remote: $name"
        return 1
    fi

    # Bare repos need this refspec to populate refs/remotes/<name>/*
    wrktr_git config "remote.$name.fetch" "+refs/heads/*:refs/remotes/$name/*"

    if _wrktr_is_dryrun; then
        return 0
    fi

    _wrktr_breaker "Remote '$name' added: $url"

    if [ -z "$WRKTR_REMOTE" ] || [ "$WRKTR_REMOTE" != "$name" ]; then
        printf '\nTo update your session config to use this remote:\n'
        printf '  1. rm ~/.config/wrktr/%s.env\n' "$WRKTR_NAME"
        printf '  2. wrktr_generate %s\n\n' "$WRKTR_NAME"
    fi

    printf 'To fetch from this remote: wrktr_update\n\n'
}

# -----------------------------------------------------------------------------
# wrktr_base
# -----------------------------------------------------------------------------
# What it does:
#   Verifies the currently-loaded wrktr session and cds into the configured
#   worktree trunk directory.
#
# Exit codes:
#   0 — cd succeeded
#   1 — validation failed
#
# Examples:
#   wrktr_base
# -----------------------------------------------------------------------------
function wrktr_base() {
    [ "$1" = "--help" ] && { wrktr_help base; return 0; }
    wrktr_validate || return 1

    _wrktr_breaker "Navigating to $WRKTR_BASE_TRUNK"

    if ! _wrktr_is_dryrun; then
        cd "$WRKTR_BASE_TRUNK" || {
            _wrktr_breaker red "Failed to cd to $WRKTR_BASE_TRUNK"
            return 1
        }
    else
        _wrktr_breaker "[DRY RUN] Would cd to: $WRKTR_BASE_TRUNK"
    fi
}

# -----------------------------------------------------------------------------
# wrktr_go
# -----------------------------------------------------------------------------
# What it does:
#   Navigates into the worktree directory for a given branch name.
#
#   Handles percent-encoding automatically so you do not need to type the
#   encoded directory name. For example, wrktr_go feature/login resolves to
#   $WRKTR_BASE_TRUNK/feature%2Flogin.
#
# Arguments:
#   $1 — branch name
#
# Exit codes:
#   0 — cd succeeded
#   1 — validation failed or worktree not found
#
# Examples:
#   wrktr_go feature/login
#   wrktr_go main
# -----------------------------------------------------------------------------
function wrktr_go() {
    [ "$1" = "--help" ] && { wrktr_help go; return 0; }
    wrktr_validate || return 1

    if [ -z "$1" ]; then
        wrktr_status
        printf 'Usage: wrktr_go <branch-name>\n\n'
        return 1
    fi

    local branch="$1"
    local safe_branch
    safe_branch="$(_wrktr_sanitize_branch_name "$branch")"
    local target="$WRKTR_BASE_TRUNK/$safe_branch"

    if _wrktr_is_dryrun; then
        _wrktr_breaker "[DRY RUN] Would cd to: $target"
        return 0
    fi

    if [ ! -d "$target" ]; then
        _wrktr_breaker red "No worktree found for branch: $branch"
        _wrktr_breaker "Expected directory: $target"
        _wrktr_breaker "Use 'wrktr list' to see active worktrees, or 'wrktr_add $branch' to create one."
        return 1
    fi

    cd "$target" || {
        _wrktr_breaker red "Failed to cd to: $target"
        return 1
    }
    _wrktr_breaker "Now in: $target"
}

# -----------------------------------------------------------------------------
# wrktr_update
# -----------------------------------------------------------------------------
# What it does:
#   Fetches updates from the configured remote.
#
# Exit codes:
#   0 — fetch succeeded
#   1 — validation or fetch failed
#
# Examples:
#   wrktr_update
# -----------------------------------------------------------------------------
# shellcheck disable=SC2120
function wrktr_update() {
    [ "$1" = "--help" ] && { wrktr_help update; return 0; }
    wrktr_validate || return 1

    if [ -z "$WRKTR_REMOTE" ]; then
        _wrktr_breaker "No remote configured; skipping update"
        return 0
    fi

    _wrktr_breaker "Updating worktree trunk"

    if ! wrktr_git fetch "$WRKTR_REMOTE"; then
        _wrktr_breaker red "Worktree trunk update failed"
        return 1
    fi

    if ! _wrktr_is_dryrun; then
        _wrktr_breaker "Worktree trunk updated"
    fi
}

# -----------------------------------------------------------------------------
# wrktr_rebase
# -----------------------------------------------------------------------------
# What it does:
#   Rebases the current branch onto:
#
#     <remote>/<main-branch>
# Must be executed from inside a worktree.
#
# Exit codes:
#   0 — rebase succeeded
#   1 — validation or rebase failed
#
# Examples:
#   wrktr_rebase
# -----------------------------------------------------------------------------
function wrktr_rebase() {
    [ "$1" = "--help" ] && { wrktr_help rebase; return 0; }
    wrktr_validate || return 1
    wrktr_update || return 1
    _wrktr_validate_worktree_context || return 1

    local current_branch
    current_branch="$(git branch --show-current)" || return 1

    if [ -z "$current_branch" ]; then
        _wrktr_breaker red "Could not determine current branch"
        return 1
    fi

    if [ "$current_branch" = "$WRKTR_MAIN_BRANCH" ]; then
        _wrktr_breaker red "Current branch is $WRKTR_MAIN_BRANCH; refusing to rebase onto itself"
        return 1
    fi

    if ! _wrktr_is_dryrun; then
        if [ -n "$(git status --porcelain)" ]; then
            _wrktr_breaker red "Working tree is dirty. Commit or stash changes before rebasing."
            return 1
        fi
    fi

    local rebase_target

    if [ -n "$WRKTR_REMOTE" ]; then
        rebase_target="$WRKTR_REMOTE/$WRKTR_MAIN_BRANCH"
    else
        rebase_target="$WRKTR_MAIN_BRANCH"
    fi

    _wrktr_breaker "Rebasing $current_branch onto $rebase_target"

    if _wrktr_is_dryrun; then
        _wrktr_breaker "[DRY RUN] git rebase $rebase_target"
        return 0
    fi

    if ! git rebase "$rebase_target"; then
        _wrktr_breaker red "Rebase failed for $current_branch onto $rebase_target"
        printf '\nIf there are conflicts, resolve them then continue:\n'
        printf '  git add <resolved-files>\n'
        printf '  git rebase --continue\n\n'
        printf 'To abandon the rebase and return to your previous state:\n'
        printf '  git rebase --abort\n\n'
        return 1
    fi

    _wrktr_breaker "Rebase completed successfully for $current_branch"
}

# -----------------------------------------------------------------------------
# wrktr_push
# -----------------------------------------------------------------------------
# What it does:
#   Pushes the current branch to the configured remote.
#
#   Must be run from inside a worktree belonging to the loaded session.
#   Refuses to push the main branch directly.
#
#   Attempts a regular push first. If rejected due to a non-fast-forward
#   conflict (normal after wrktr_rebase), prompts before retrying with
#   --force-with-lease, which is the safe force-push option for rebase
#   workflows.
#
# Exit codes:
#   0 — push succeeded
#   1 — validation or push failed
#
# Examples:
#   wrktr_push
# -----------------------------------------------------------------------------
function wrktr_push() {
    [ "$1" = "--help" ] && { wrktr_help push; return 0; }
    wrktr_validate || return 1
    _wrktr_validate_worktree_context || return 1

    if [ -z "$WRKTR_REMOTE" ]; then
        _wrktr_breaker red "No remote configured for this session."
        _wrktr_breaker "Add a remote first: wrktr_remote_add <name> <url>"
        return 1
    fi

    local current_branch
    current_branch="$(git branch --show-current)" || return 1

    if [ -z "$current_branch" ]; then
        _wrktr_breaker red "Could not determine current branch. Are you in a detached HEAD state?"
        return 1
    fi

    if [ "$current_branch" = "$WRKTR_MAIN_BRANCH" ]; then
        _wrktr_breaker red "Refusing to push the main branch ($WRKTR_MAIN_BRANCH) directly."
        _wrktr_breaker "Push feature branches, not main."
        return 1
    fi

    if _wrktr_is_dryrun; then
        _wrktr_breaker "[DRY RUN] Would push $current_branch to $WRKTR_REMOTE"
        return 0
    fi

    _wrktr_breaker "Pushing $current_branch to $WRKTR_REMOTE"

    if git push "$WRKTR_REMOTE" "$current_branch"; then
        _wrktr_breaker "Pushed $current_branch successfully"
        return 0
    fi

    _wrktr_breaker yellow "Push was rejected."
    printf '\nThis usually means the remote has commits not in your local history,\n'
    printf 'which is expected after wrktr_rebase.\n\n'
    printf 'Push with --force-with-lease? Safe when no one else has pushed to\n'
    printf 'this branch since your last fetch. [y/N]: '

    local answer
    read -r answer </dev/tty
    case "$answer" in
        y|Y|yes|YES)
            if git push --force-with-lease "$WRKTR_REMOTE" "$current_branch"; then
                _wrktr_breaker "Pushed $current_branch with --force-with-lease"
                return 0
            else
                _wrktr_breaker red "Force push failed."
                _wrktr_breaker "The remote branch was updated by someone else since your last fetch."
                _wrktr_breaker "Run wrktr_rebase to incorporate those changes, then push again."
                return 1
            fi
            ;;
        *)
            _wrktr_breaker "Push cancelled."
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# wrktr
# -----------------------------------------------------------------------------
# What it does:
#   Thin wrapper around:
#
#     git worktree
#
# Arguments:
#   Everything after `wrktr` is passed directly to:
#
#     git worktree
#
# Exit codes:
#   Same as underlying git worktree command.
#
# Examples:
#   wrktr list
#   wrktr prune
# -----------------------------------------------------------------------------
function wrktr() {
    [ "$1" = "--help" ] && { wrktr_help wrktr; return 0; }
    wrktr_validate || return 1

    if [ "$#" -lt 1 ]; then
        _wrktr_breaker red "Usage: wrktr <worktree-subcommand> [args...]"
        return 1
    fi

    _wrktr_breaker "Running: git worktree $*"

    wrktr_git worktree "$@"
}

# -----------------------------------------------------------------------------
# wrktr_add
# -----------------------------------------------------------------------------
# What it does:
#   Creates a new linked worktree under:
#
#     $WRKTR_BASE_TRUNK/<sanitized-branch-name>
#
# Arguments:
#   $1 — branch name
#   $2 — optional base ref
#
# Exit codes:
#   0 — worktree created
#   1 — validation or add failed
#
# Examples:
#   wrktr_add feature/test
# -----------------------------------------------------------------------------
function wrktr_add() {
    [ "$1" = "--help" ] && { wrktr_help add; return 0; }
    wrktr_validate || return 1

    if [ -z "$1" ]; then
        _wrktr_breaker red "Usage: wrktr_add <branch-name> [base-ref]"
        return 1
    fi

    local branch="$1"
    # local base_ref="${2:-$WRKTR_REMOTE/$WRKTR_MAIN_BRANCH}"
    local base_ref

    if [ -n "$2" ]; then
        base_ref="$2"
    elif [ -n "$WRKTR_REMOTE" ]; then
        base_ref="$WRKTR_REMOTE/$WRKTR_MAIN_BRANCH"
        wrktr_update || return 1
    else
        base_ref="$WRKTR_MAIN_BRANCH"
    fi

    if _wrktr_is_dryrun; then
        _wrktr_breaker "[DRY RUN] Would verify base ref: $base_ref"
    elif ! git --git-dir="$WRKTR_BASE_DIR" rev-parse --verify "$base_ref" >/dev/null 2>&1; then
        _wrktr_breaker red "Base ref does not exist: $base_ref"
        return 1
    fi

    if ! _wrktr_create_worktree \
        "$WRKTR_BASE_DIR" \
        "$WRKTR_BASE_TRUNK" \
        "$branch" \
        "$base_ref"; then
        return 1
    fi

    local safe_branch
    safe_branch="$(_wrktr_sanitize_branch_name "$branch")"

    local target="$WRKTR_BASE_TRUNK/$safe_branch"

    if ! _wrktr_is_dryrun; then
        if [ ! -d "$target" ]; then
            _wrktr_breaker red "Worktree does not exist: $target"
            return 1
        fi
    fi

    wrktr_status

    if ! _wrktr_is_dryrun; then
        cd "$target" || {
            _wrktr_breaker red "Worktree created but failed to cd into: $target"
            return 1
        }
    fi
}

# -----------------------------------------------------------------------------
# wrktr_checkout
# -----------------------------------------------------------------------------
# What it does:
#   Creates a local worktree for a branch that already exists on the remote.
#
#   Use this to work on a colleague's branch or to pick up work that was
#   started elsewhere. Unlike wrktr_add (which creates a new branch),
#   wrktr_checkout requires the branch to already exist on the configured
#   remote.
#
#   The local branch is created tracking the remote branch so that subsequent
#   git pull and push operations work without additional arguments.
#
# Arguments:
#   $1 — branch name (must already exist on the configured remote)
#
# Exit codes:
#   0 — worktree created
#   1 — validation or checkout failed
#
# Examples:
#   wrktr_checkout feature/login
# -----------------------------------------------------------------------------
function wrktr_checkout() {
    [ "$1" = "--help" ] && { wrktr_help checkout; return 0; }
    wrktr_validate || return 1

    if [ -z "$1" ]; then
        _wrktr_breaker red "Usage: wrktr_checkout <branch-name>"
        _wrktr_breaker "The branch must already exist on the configured remote."
        return 1
    fi

    if [ -z "$WRKTR_REMOTE" ]; then
        _wrktr_breaker red "No remote configured. wrktr_checkout requires a remote."
        _wrktr_breaker "To create a new local branch instead: wrktr_add <branch> <base-ref>"
        return 1
    fi

    local branch="$1"
    local remote_ref="$WRKTR_REMOTE/$branch"
    local safe_branch
    safe_branch="$(_wrktr_sanitize_branch_name "$branch")"
    local target="$WRKTR_BASE_TRUNK/$safe_branch"

    wrktr_update || return 1

    if ! _wrktr_is_dryrun; then
        if ! git --git-dir="$WRKTR_BASE_DIR" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
            _wrktr_breaker red "Remote branch not found: $remote_ref"
            printf '\nAvailable remote branches:\n'
            local _remote="$WRKTR_REMOTE"
            git --git-dir="$WRKTR_BASE_DIR" branch -r 2>/dev/null \
                | grep -F "  $_remote/" \
                | while IFS= read -r _ref; do printf '%s\n' "${_ref#"  $_remote/"}"; done \
                | head -20
            printf '\n'
            return 1
        fi

        if [ -d "$target" ]; then
            _wrktr_breaker red "A worktree for this branch already exists: $target"
            _wrktr_breaker "Use 'wrktr_go $branch' to navigate to it."
            return 1
        fi

        if git --git-dir="$WRKTR_BASE_DIR" show-ref --verify --quiet "refs/heads/$branch"; then
            _wrktr_breaker red "Local branch '$branch' already exists but has no worktree."
            _wrktr_breaker "Use 'wrktr_add $branch' to create a worktree for the existing branch."
            return 1
        fi
    fi

    _wrktr_breaker "Checking out $remote_ref"

    if ! _wrktr_create_worktree \
        "$WRKTR_BASE_DIR" \
        "$WRKTR_BASE_TRUNK" \
        "$branch" \
        "$remote_ref"; then
        return 1
    fi

    if ! _wrktr_is_dryrun; then
        git --git-dir="$WRKTR_BASE_DIR" branch \
            --set-upstream-to="$remote_ref" "$branch" 2>/dev/null || true

        wrktr_status

        cd "$target" || {
            _wrktr_breaker red "Worktree created but failed to cd into: $target"
            return 1
        }
    fi
}

# -----------------------------------------------------------------------------
# wrktr_remove
# -----------------------------------------------------------------------------
# What it does:
#   Removes a linked worktree.
#
# Arguments:
#   $1 — branch name
#
# Exit codes:
#   0 — worktree removed
#   1 — validation or remove failed
#
# Examples:
#   wrktr_remove feature/test
# -----------------------------------------------------------------------------
function wrktr_remove() {
    [ "$1" = "--help" ] && { wrktr_help remove; return 0; }
    wrktr_validate || return 1

    if [ -z "$1" ]; then
        _wrktr_breaker red "Usage: wrktr_remove <branch-name>"
        return 1
    fi

    local branch="$1"

    if [ "$branch" = "$WRKTR_MAIN_BRANCH" ]; then
        _wrktr_breaker red "Refusing to remove the main branch worktree ($WRKTR_MAIN_BRANCH)."
        _wrktr_breaker "The main worktree is the primary workspace of the project."
        return 1
    fi

    local safe_branch
    safe_branch="$(_wrktr_sanitize_branch_name "$branch")"

    local target="$WRKTR_BASE_TRUNK/$safe_branch"

    local resolved_pwd resolved_target
    resolved_pwd="$(pwd -P 2>/dev/null || printf '%s' "$PWD")"
    resolved_target="$(cd "$target" 2>/dev/null && pwd -P 2>/dev/null || printf '%s' "$target")"
    case "$resolved_pwd" in
        "$resolved_target"/*|"$resolved_target")
            _wrktr_breaker red "Cannot remove worktree while inside it. Please cd out first."
            return 1
            ;;
    esac

    if ! _wrktr_is_dryrun; then
        if [ ! -d "$target" ]; then
            _wrktr_breaker red "Worktree directory not found: $target"
            _wrktr_breaker "If it was manually deleted, run: wrktr prune"
            return 1
        fi
    fi

    _wrktr_breaker "Removing worktree $target"

    if ! wrktr_git worktree remove "$target"; then
        _wrktr_breaker red "Worktree remove failed"
        _wrktr_breaker "If the worktree has uncommitted changes, commit or stash them first."
        return 1
    fi

    wrktr_git worktree prune

    if ! _wrktr_is_dryrun; then
        _wrktr_breaker "Worktree $target removed successfully"
        printf '\nBranch "%s" still exists in the bare repository.\n' "$branch"
        printf 'Delete it? [y/N]: '
        local del_branch_answer
        read -r del_branch_answer </dev/tty
        case "$del_branch_answer" in
            y|Y|yes|YES)
                if wrktr_git branch -d "$branch" 2>/dev/null; then
                    _wrktr_breaker "Branch $branch deleted"
                else
                    printf '\nBranch "%s" has unmerged changes.\n' "$branch"
                    printf 'Force delete anyway? This cannot be undone. [y/N]: '
                    local force_del_answer
                    read -r force_del_answer </dev/tty
                    case "$force_del_answer" in
                        y|Y|yes|YES)
                            if wrktr_git branch -D "$branch"; then
                                _wrktr_breaker "Branch $branch force-deleted"
                            else
                                _wrktr_breaker red "Failed to delete branch $branch"
                            fi
                            ;;
                        *)
                            printf 'Branch kept. To delete later: wrktr_git branch -d %s\n\n' "$branch"
                            ;;
                    esac
                fi
                ;;
            *)
                printf 'Branch kept. To delete later: wrktr_git branch -d %s\n\n' "$branch"
                ;;
        esac
    fi

    wrktr_status
}

# -----------------------------------------------------------------------------
# wrktr_unload
# -----------------------------------------------------------------------------
# What it does:
#   Removes all wrktr functions and variables from the current shell.
#
#   Use this when you want to reload a modified version of the file, cleanly
#   remove wrktr from a session, or test changes from scratch.
#
#   Note: removes all functions matching ^_?wrktr (i.e. wrktr_* and _wrktr_*).
#   If you have your own functions with a wrktr_ or _wrktr_ prefix they will
#   also be removed.
#
# Exit codes:
#   0 — always
#
# Examples:
#   wrktr_unload
# -----------------------------------------------------------------------------
# shellcheck disable=SC2120
function wrktr_unload() {
    [ "$1" = "--help" ] && { wrktr_help unload; return 0; }
    local f
    while IFS= read -r f; do
        unset -f "$f"
    done < <(compgen -A function | grep -E '^_?wrktr')

    unset WRKTR_VERSION
    unset WRKTR_NAME
    unset WRKTR_BASE_TRUNK
    unset WRKTR_BASE_DIR
    unset WRKTR_REMOTE
    unset WRKTR_MAIN_BRANCH
    unset WRKTR_CONFIG_DIR
    unset WRKTR_DRY_RUN
    unset WRKTR_REPO_DIR_NAME
    unset WRKTR_SOURCE_PATH
}

# -----------------------------------------------------------------------------
# wrktr_reload
# -----------------------------------------------------------------------------
# What it does:
#   Unloads all wrktr functions and variables, then re-sources the file from
#   the path it was originally loaded from.
#
#   Use this after modifying worktree-functions.sh to pick up the changes
#   without starting a new shell.
#
# Exit codes:
#   0 — reload succeeded
#   1 — source path unknown or file not found
#
# Examples:
#   wrktr_reload
# -----------------------------------------------------------------------------
function wrktr_reload() {
    [ "$1" = "--help" ] && { wrktr_help reload; return 0; }
    local src="$WRKTR_SOURCE_PATH"
    if [ -z "$src" ]; then
        printf 'wrktr: cannot reload — WRKTR_SOURCE_PATH is not set\n' >&2
        return 1
    fi
    if [ ! -f "$src" ]; then
        printf 'wrktr: cannot reload — file not found: %s\n' "$src" >&2
        return 1
    fi
    # shellcheck disable=SC2119
    wrktr_unload
    # shellcheck disable=SC1090
    source "$src"
}

# =============================================================================
# TAB COMPLETION
# =============================================================================
#
# Bash completion is registered automatically when this file is sourced in a
# bash shell. In zsh, enable bash completion first:
#
#   autoload -U +X bashcompinit && bashcompinit
#   source /path/to/worktree-functions.sh
#
# =============================================================================

# -----------------------------------------------------------------------------
# Completion data helpers
# -----------------------------------------------------------------------------

function _wrktr_sessions() {
    local config_dir="${WRKTR_CONFIG_DIR:-$HOME/.config/wrktr}"
    if [ -d "$config_dir" ]; then
        local f
        for f in "$config_dir"/*.env; do
            [ -e "$f" ] && basename "$f" .env
        done
    fi
}

function _wrktr_local_branches() {
    [ -z "$WRKTR_BASE_DIR" ] && return
    git --git-dir="$WRKTR_BASE_DIR" branch --format='%(refname:short)' 2>/dev/null
}

function _wrktr_remote_branches() {
    [ -z "$WRKTR_BASE_DIR" ] || [ -z "$WRKTR_REMOTE" ] && return
    local _remote="$WRKTR_REMOTE"
    git --git-dir="$WRKTR_BASE_DIR" branch -r --format='%(refname:short)' 2>/dev/null \
        | while IFS= read -r _ref; do printf '%s\n' "${_ref#"$_remote/"}"; done
}

function _wrktr_worktree_branches() {
    [ -z "$WRKTR_BASE_DIR" ] && return
    git --git-dir="$WRKTR_BASE_DIR" worktree list --porcelain 2>/dev/null \
        | grep '^branch ' \
        | sed 's|branch refs/heads/||'
}

# -----------------------------------------------------------------------------
# Completion handlers
# -----------------------------------------------------------------------------
# SC2207: mapfile/read -a are not available in bash 3.2 (the macOS default).
# COMPREPLY=($(compgen ...)) is the correct pattern for bash 3.2 compatibility.

# shellcheck disable=SC2207
function _wrktr_complete_use() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "$(_wrktr_sessions)" -- "$cur"))
}

# shellcheck disable=SC2207
function _wrktr_complete_go() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "$(_wrktr_worktree_branches)" -- "$cur"))
}

# shellcheck disable=SC2207
function _wrktr_complete_remove() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local main="${WRKTR_MAIN_BRANCH:-main}"
    COMPREPLY=($(compgen -W "$(_wrktr_worktree_branches | grep -v "^${main}$")" -- "$cur"))
}

# shellcheck disable=SC2207
function _wrktr_complete_checkout() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "$(_wrktr_remote_branches)" -- "$cur"))
}

# shellcheck disable=SC2207
function _wrktr_complete_add() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    case $COMP_CWORD in
        1) COMPREPLY=($(compgen -W "$(_wrktr_local_branches)" -- "$cur")) ;;
        2) COMPREPLY=($(compgen -W "$(_wrktr_local_branches) $(_wrktr_remote_branches)" -- "$cur")) ;;
    esac
}

# shellcheck disable=SC2207
function _wrktr_complete_git() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local subcmds="fetch pull push log branch status diff show worktree remote tag stash"
    case $COMP_CWORD in
        1) COMPREPLY=($(compgen -W "$subcmds" -- "$cur")) ;;
        *) COMPREPLY=($(compgen -W "$(_wrktr_local_branches) $(_wrktr_remote_branches)" -- "$cur")) ;;
    esac
}

# shellcheck disable=SC2207
function _wrktr_complete_passthrough() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local subcmds="list add remove lock unlock move prune repair"
    case $COMP_CWORD in
        1) COMPREPLY=($(compgen -W "$subcmds" -- "$cur")) ;;
        *) COMPREPLY=($(compgen -W "$(_wrktr_worktree_branches)" -- "$cur")) ;;
    esac
}

# Register completions only when the complete builtin is available.
# In zsh without bashcompinit this is silently skipped.
if type complete >/dev/null 2>&1; then
    complete -F _wrktr_complete_use      wrktr_use
    complete -F _wrktr_complete_go       wrktr_go
    complete -F _wrktr_complete_remove   wrktr_remove
    complete -F _wrktr_complete_checkout wrktr_checkout
    complete -F _wrktr_complete_add      wrktr_add
    complete -F _wrktr_complete_git      wrktr_git
    complete -F _wrktr_complete_passthrough wrktr
fi

# =============================================================================
# WORKTREE HELPERS (wrktr*) — END
# =============================================================================

_wrktr_breaker green "Worktree functions loaded"