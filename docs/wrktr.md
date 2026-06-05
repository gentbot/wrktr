# wrktr — Branch-as-Directory Workflow Tool

`wrktr` is a shell tool that treats git branches as persistent directories rather than transient checkout states. Instead of switching branches with `git checkout`, you switch contexts by changing directories. Every branch you are actively working on has its own permanent folder on disk. You `cd` into it to work on it. You `cd` out when you are done. Nothing is ever stashed, interrupted, or lost.

---

## The core idea

In a standard git workflow, a repository has one working tree. To move between branches you run `git checkout`, which overwrites your files with the state of the new branch. If you have in-progress work you have to stash it, commit it, or lose it. Your editor, build tools, and test runners all point at the same directory — and that directory changes underneath them every time you switch.

`wrktr` takes a different approach. Each branch gets its own directory:

```
~/<code_location>/
    main/                   ← main branch, always here
    feature%2Flogin/        ← feature/login, always here
    fix%2Fcrash/            ← fix/crash, always here
```

All three exist simultaneously. Moving between them is `cd`. Your editor can have all three open at once. A build running in one directory is completely unaffected by work in another. When you finish a feature and remove its worktree, the other directories are untouched.

`git checkout` is never used. Branches are not states you visit — they are places you live in.

---

## Why this requires a bare repository

A normal git repository has a working tree with a `.git` subdirectory. You can attach additional worktrees to it with `git worktree add`, but the original checkout always occupies a privileged position: it owns the HEAD and cannot be removed. If you check out a different branch there, you disrupt whatever was there before.

`wrktr` uses a **bare repository** — a git database with no working tree of its own. The bare repository is pure storage: all commits, branches, history, and remotes, but no files you would ever edit. Every branch checkout exists as an equal, removable linked worktree. There is no "main" checkout that owns the HEAD.

```
~/<code_location>/
    .wrktr/             ← bare git database (no files, just git internals)
    main/               ← linked worktree for main
    feature%2Flogin/    ← linked worktree for feature/login
```

`.wrktr` holds the git state for all worktrees. Each worktree directory contains a `.git` file — a single line pointing back to `.wrktr`. The worktrees are peers. Any of them can be created or removed without affecting the others.

Because the bare database has no working tree, git cannot auto-detect it by walking up from your current directory. Commands that need to reach the database from outside a worktree must pass `--git-dir` explicitly. `wrktr_git` handles this automatically.

---

## Requirements

- bash 3.2 or later (the macOS default is sufficient; bash 4+ is not required)
- git 2.7 or later (`git worktree list --porcelain` required by `wrktr_status`); git 2.36 or later required for `wrktr_init`
- rsync (required only by `wrktr_init`)

---

## Loading the functions

```bash
source /path/to/worktree-functions.sh
```

Source this in your shell profile or manually in any session. All function names are prefixed `wrktr_` (public) or `_wrktr_` (internal).

---

## Shell integration

### Auto-load on shell start

Add to `~/.bashrc` or `~/.zshrc`:

```bash
source /path/to/worktree-functions.sh
```

### Tab completion

Tab completion is built into `worktree-functions.sh` and registers automatically when the file is sourced in bash.

For zsh, enable bash completion before sourcing:

```bash
# ~/.zshrc
autoload -U +X bashcompinit && bashcompinit
source /path/to/worktree-functions.sh
```

Tab completion is available for:
- `wrktr_use` — session names
- `wrktr_go`, `wrktr_remove` — branches with active worktrees
- `wrktr_checkout` — remote branches
- `wrktr_add` — existing branches (for the optional base-ref argument)
- `wrktr_git`, `wrktr` — git subcommands and branch names

### Prompt integration

`wrktr_prompt_info` outputs a short context string suitable for embedding in `PS1`. It prints nothing when no session is loaded, so it is safe to include unconditionally.

```bash
# Add to ~/.bashrc or ~/.zshrc:
PS1='$(wrktr_prompt_info) \$ '

# Example output when inside a worktree:
# [myapp:feature/login] $

# Example output when in a session but not a worktree:
# [myapp] $
```

---

## Daily workflow

### Starting a branch

```bash
wrktr_add feature/login
```

Creates a new branch, creates a directory for it, and `cd`s into it automatically.

### Checking out a colleague's branch

```bash
wrktr_checkout feature/login
```

For branches that already exist on the remote. Fetches, creates a local worktree, sets up upstream tracking, and `cd`s in.

### Navigating between worktrees

```bash
wrktr_go feature/login
wrktr_go main
wrktr_go            # no arg: shows status of all worktrees, then usage
```

### Seeing everything at a glance

```bash
wrktr_status
```

Shows all active worktrees: branch name, commits ahead/behind main, and whether each has uncommitted changes.

### Keeping a branch current

```bash
cd ~/<code_location>/feature%2Flogin
wrktr_rebase
```

Fetches from the remote and rebases the current branch onto the latest main.

### Pushing work

```bash
wrktr_push
```

Pushes the current branch. If rejected after a rebase, prompts before retrying with `--force-with-lease`.

### Finishing a branch

```bash
wrktr_remove feature/login
```

Removes the worktree directory, prunes the reference, then prompts whether to delete the local branch ref.

---

## Project setup

There are three entry points depending on your starting point.

---

### Starting from an existing remote repo — `wrktr_clone`

```bash
wrktr_clone https://github.com/user/myapp.git
# or with SSH:
wrktr_clone git@github.com:user/myapp.git
# or with an explicit destination:
wrktr_clone https://github.com/user/myapp.git ~/projects/myapp
```

Creates the trunk directory, runs a bare clone, fixes the fetch refspec, fetches all remote refs, detects the main branch, and creates the initial worktree at `main/`.

After cloning, `wrktr_clone` prints the exact values to enter when `wrktr_generate` prompts.

---

### Converting an existing local clone — `wrktr_adopt`

Use this when you already have a normal `git clone` and want to switch to the wrktr workflow.

```bash
wrktr_adopt ~/projects/myapp
```

Or interactively:

```bash
wrktr_adopt
# Path to existing git clone: ~/projects/myapp
# Main branch [main]:
# New trunk directory [~/projects/myapp-wrktr]:
```

Creates a bare clone from the existing repo, restores any remote the original had, and creates the main worktree. The original clone is not touched — remove it manually once the new structure is confirmed working.

After adopting, `wrktr_adopt` prints the exact values to enter when `wrktr_generate` prompts.

---

### Starting from a new local project — `wrktr_init`

Use this for brand new projects with no remote history.

```bash
mkdir -p ~/<code_location>/code
# place existing files in omi/code, or leave it empty
wrktr_init
```

```
Project root path: ~/<code_location>
Main worktree directory [main]: main
Main branch [main]: main
```

After completion, run `wrktr_generate` to create the session config.

To connect to a remote later:

```bash
wrktr_remote_add origin https://github.com/user/omi.git
```

---

### Session config — `wrktr_generate` and `wrktr_use`

After any setup path, create the session config:

```bash
wrktr_generate omi
```

Then load it in any shell:

```bash
wrktr_use omi
```

The session is shell-scoped. New terminals start with nothing loaded — run `wrktr_use` again each time.

Each shell manages its own session independently. Running `wrktr_use myapp` in one terminal does not affect other terminals. Two shells can load the same session simultaneously — they both read the same config file and both point at the same bare repository without interfering. What they cannot do is share state changes: switching sessions in one shell is invisible to all others. This is intentional.

---

## Working across multiple projects

```bash
wrktr_list          # see all available project configs
wrktr_use omi       # load the omi project
wrktr_use myapp     # switch to a different project
wrktr_current       # show what is currently loaded
wrktr_config_show   # show the raw config file for the loaded session
```

---

## Function reference

Every command supports `--help` for inline documentation:

```bash
wrktr_add --help
wrktr_remove --help
wrktr_clone --help
```

`wrktr_help` also accepts a command name directly:

```bash
wrktr_help add
wrktr_help wrktr_add    # both forms work
wrktr_help              # show all commands
```

---

### Help

---

#### `wrktr_help`

Displays command documentation.

```bash
wrktr_help              # list all commands with one-line descriptions
wrktr_help add          # full documentation for wrktr_add
wrktr_help wrktr_add    # same — both the short name and full name are accepted
```

Each command also responds to `--help` as its first argument, so you don't need to remember the separate `wrktr_help` invocation:

```bash
wrktr_add --help
wrktr_rebase --help
wrktr_clone --help
```

Works without a session loaded.

---

### Setup

---

#### `wrktr_clone`

Clones an existing remote repository into a wrktr-compatible bare repository structure.

```bash
wrktr_clone https://github.com/user/myapp.git
wrktr_clone git@github.com:user/myapp.git ~/projects/myapp
```

| Argument | Required | Description |
|----------|----------|-------------|
| `url` | yes | Remote URL. Handles both HTTPS and SSH URL formats. |
| `destination` | no | Local directory to create. Defaults to the repo name from the URL in the current directory. Must be at least two directory levels deep. |

Applies the fetch refspec fix required for bare clones and runs an initial fetch so `origin/main` references work immediately. If the repository is empty, creates the bare database and prints instructions.

After cloning, run `wrktr_generate` then `wrktr_use`.

---

#### `wrktr_adopt`

Converts an existing normal git clone into a wrktr-compatible bare repository structure.

```bash
wrktr_adopt ~/projects/myapp
wrktr_adopt           # interactive prompts
```

| Prompt | Default | Description |
|--------|---------|-------------|
| `Path to existing git clone` | none | Must be a directory with a `.git` subdirectory. |
| `Main branch` | detected from HEAD | Branch to use as the main worktree. |
| `New trunk directory` | `<parent>/<name>-wrktr` | Where to create the new structure. |

Creates a bare clone of the existing repo, removes the auto-added local-path remote, restores the original upstream remote if one existed, and creates the main worktree. The original clone is unchanged.

After adopting, run `wrktr_generate` then `wrktr_use`.

---

#### `wrktr_init`

Initializes a new bare repository from an existing local project directory. One-time operation per project. Use for brand new projects with no remote.

```bash
wrktr_init
```

| Prompt | Default | Description |
|--------|---------|-------------|
| `Project root path` | none | Must exist. Must be at least two directory levels deep. |
| `Main worktree directory` | `main` | Simple name — no `/`, `.`, or `..`. Must already exist inside the project root. The name can be anything; `main` is just the default. |
| `Main branch` | `main` | Name for the initial branch. |

On failure, a rollback routine runs and prompts before removing anything it created.

---

#### `wrktr_generate`

Creates a project config and saves it to `~/.config/wrktr/<name>.env`.

```bash
wrktr_generate          # prompts for all values
wrktr_generate omi      # session name pre-supplied
```

| Prompt | Default | Description |
|--------|---------|-------------|
| `Session name` | none | Letters, digits, dots, hyphens, underscores only. |
| `Base trunk path` | none | The trunk directory containing `.wrktr`. Must exist. |
| `Remote name` | none | Git remote name, typically `origin`. Leave empty for local-only projects. |
| `Main branch` | `main` | Primary integration branch. |

---

#### `wrktr_remote_add`

Adds a remote to the loaded session's bare repository.

```bash
wrktr_remote_add origin https://github.com/user/myapp.git
```

Sets up the correct fetch refspec for bare repositories automatically. After adding, update the session config:

```bash
wrktr_config_edit    # add the remote name to WRKTR_REMOTE, then wrktr_use to reload
```

---

### Session

---

#### `wrktr_use`

Loads a project config into the current shell.

```bash
wrktr_use omi
```

Sources `~/.config/wrktr/omi.env`. If validation fails, all variables are unset so the shell is not left in a partial state.

---

#### `wrktr_list`

Lists all available project configs in `~/.config/wrktr/`.

```bash
wrktr_list
```

Does not require a project to be loaded.

---

#### `wrktr_current`

Shows the loaded project's configuration values.

```bash
wrktr_current
```

Prints session name, trunk path, bare database path, remote, and main branch.

---

#### `wrktr_config_show`

Displays the path and full contents of the loaded session's config file.

```bash
wrktr_config_show
```

Useful for debugging a broken session or confirming stored values. If the config file has been deleted since the session was loaded, reports the missing file and suggests recreating it with `wrktr_generate`.

---

#### `wrktr_config_edit`

Opens the loaded session's config file in `$EDITOR` for manual editing.

```bash
wrktr_config_edit
```

Use this to update a remote URL, change the main branch name, or correct any stored value without deleting and regenerating the config. After the editor closes, `wrktr_validate` runs automatically to confirm the file is valid. The edit is preserved even if validation fails — run `wrktr_config_edit` again to correct mistakes. Changes are not applied to the current shell automatically; run `wrktr_use <session>` after editing to pick up the new values.

Falls back to `vi` if `$EDITOR` is not set.

---

#### `wrktr_status`

Shows the status of all active worktrees for the loaded session.

```bash
wrktr_status
```

For each worktree, displays branch name, commits ahead of or behind the main branch ref, dirty state, and full path. Uses `origin/<main-branch>` as the comparison ref when a remote is configured.

---

#### `wrktr_validate`

Validates the currently-loaded session. Called automatically by most commands.

```bash
wrktr_validate
```

---

#### `wrktr_prompt_info`

Outputs a context string for shell prompt embedding.

```bash
wrktr_prompt_info
# prints:  [myapp:feature/login]
# or:      [myapp]   (when not inside a worktree)
# or:      (nothing) (when no session is loaded)
```

Embed in `PS1`:

```bash
# ~/.bashrc or ~/.zshrc
PS1='$(wrktr_prompt_info) \$ '
```

---

### Daily operations

---

#### `wrktr_add`

Creates a new branch and worktree directory, then `cd`s into it.

```bash
wrktr_add feature/login              # branch from origin/main (fetches first)
wrktr_add fix/crash origin/v2        # branch from a specific ref
wrktr_add experiment/auth main       # branch from local main
```

| Argument | Required | Description |
|----------|----------|-------------|
| `branch-name` | yes | Name for the new branch. Must not already exist. |
| `base-ref` | no | Ref to branch from. Defaults to `origin/<main-branch>` with a remote, or `<main-branch>` without. |

---

#### `wrktr_checkout`

Creates a local worktree for a branch that already exists on the remote.

```bash
wrktr_checkout feature/login
```

Fetches first, verifies the remote branch exists (lists available ones if not), creates the local worktree, sets up upstream tracking, and `cd`s in. Requires a remote to be configured.

---

#### `wrktr_go`

Navigates into a worktree by branch name. Handles percent-encoding automatically.

```bash
wrktr_go feature/login   # cd to feature%2Flogin/
wrktr_go main
wrktr_go                 # no arg: shows wrktr_status then usage
```

---

#### `wrktr_rebase`

Fetches from the remote and rebases the current branch onto the latest main.

```bash
cd ~/<code_location>/feature%2Flogin
wrktr_rebase
```

Must be run from inside a worktree belonging to the loaded project. Refuses if on the main branch or if the working tree has uncommitted changes. On conflict: resolve then `git rebase --continue`. To abandon: `git rebase --abort`.

---

#### `wrktr_push`

Pushes the current branch to the configured remote.

```bash
wrktr_push
```

Must be run from inside a worktree belonging to the loaded project. Refuses to push the main branch. Attempts a regular push first; if rejected (expected after a rebase), prompts before retrying with `--force-with-lease`. Requires a remote to be configured.

---

#### `wrktr_remove`

Removes a worktree directory, prunes its reference, and optionally deletes the branch.

```bash
wrktr_remove feature/login
```

Refuses to remove the main branch worktree. Refuses if there are uncommitted changes in the worktree. After removal, prompts whether to delete the local branch ref — if the branch has unmerged changes, a second confirmation is required before force-deleting.

---

#### `wrktr_update`

Fetches from the configured remote.

```bash
wrktr_update
```

Updates all remote tracking refs in the bare database without touching any worktree. Silently succeeds with no action if no remote is configured. Called automatically by `wrktr_add`, `wrktr_rebase`, and `wrktr_checkout`.

---

#### `wrktr_base`

Navigates to the trunk directory.

```bash
wrktr_base
```

`cd`s to `$WRKTR_BASE_TRUNK`, where all worktree directories and `.wrktr` are visible side by side.

---

### Git access

---

#### `wrktr_git`

Runs any git command against the bare database by supplying `--git-dir` automatically.

```bash
wrktr_git fetch origin
wrktr_git branch -d feature/login
wrktr_git log --oneline main
wrktr_git remote -v
```

Use from outside a worktree. From inside a worktree, ordinary `git` commands work without it.

---

#### `wrktr`

Raw passthrough to `git worktree` via the bare database.

```bash
wrktr list
wrktr prune
wrktr lock feature%2Flogin
```

---

### Dry-run mode

Prints every mutating command without executing it. Validation still runs.

```bash
wrktr_dryrun_enable
wrktr_add feature/test      # shows what would happen, does nothing
wrktr_dryrun_disable
```

---

### Lifecycle

---

#### `wrktr_unload`

Removes all wrktr functions and environment variables from the current shell.

```bash
wrktr_unload
```

Useful when you want to reload a modified version of the file, cleanly remove wrktr from a session, or verify behavior from a fresh state. Removes all `wrktr_*` and `_wrktr_*` functions and unsets all `WRKTR_*` environment variables.

---

#### `wrktr_reload`

Unloads all wrktr functions and re-sources the file from its original path.

```bash
wrktr_reload
```

Use this after editing `worktree-functions.sh` to pick up changes without opening a new shell. The source path is captured automatically when the file is first sourced.

---

## Deletion safety

Every `rm -rf` in `wrktr` goes through two checks before anything is removed. These apply during `wrktr_init` and `wrktr_adopt` — the only places `wrktr` calls `rm` directly.

**Subpath containment:** The target is resolved to its real absolute path via `pwd -P`. It must fall inside the project root. If it resolves outside, the operation is rejected.

**Confirmation prompt:** The resolved path is displayed. You must type `y`, `Y`, `yes`, or `YES`. Anything else, including Enter, cancels.

`wrktr_remove` delegates to `git worktree remove` — git's own mechanism — and does not call `rm` directly.

---

## Branch name encoding

`/` in a branch name would create nested directories. `wrktr` percent-encodes branch names before using them as directory names:

| Character | Encoded as |
|-----------|-----------|
| `%` | `%25` (first, to avoid double-encoding) |
| `/` | `%2F` |

| Branch name | Directory name |
|------------|---------------|
| `main` | `main` |
| `feature/login` | `feature%2Flogin` |
| `fix/crash-100%` | `fix%2Fcrash-100%25` |

All `wrktr_*` commands accept original branch names. `wrktr_go` also handles encoding automatically so you never need to type encoded names.

---

## Session environment variables

| Variable | Description |
|----------|-------------|
| `WRKTR_NAME` | Project name — matches the config filename |
| `WRKTR_BASE_TRUNK` | Absolute path to the trunk directory containing `.wrktr` and all worktrees |
| `WRKTR_BASE_DIR` | Absolute path to the bare git database (`$WRKTR_BASE_TRUNK/.wrktr`). Passed as `--git-dir` to every git command. |
| `WRKTR_REMOTE` | Git remote name. Empty if no remote is configured. |
| `WRKTR_MAIN_BRANCH` | Primary branch name |
| `WRKTR_DRY_RUN` | `1` when dry-run is active, `0` otherwise |
| `WRKTR_REPO_DIR_NAME` | Name of the bare git database directory. Defaults to `.wrktr`. Set before sourcing to override. |
| `WRKTR_SOURCE_PATH` | Absolute path to `worktree-functions.sh` as loaded. Used by `wrktr_reload`. |

### Why `.wrktr` and not `.git`

The bare database is named `.wrktr` rather than `.git` for two reasons. First, git itself and many tools assume that a directory named `.git` inside a project is a normal (non-bare) repository — using `.git` for the bare database confuses tooling. Second, `.wrktr` makes the structure immediately recognizable as a wrktr-managed project.

To use a different name, set `WRKTR_REPO_DIR_NAME` before sourcing the file:

```bash
export WRKTR_REPO_DIR_NAME=".bare"
source /path/to/worktree-functions.sh
```

This only affects project creation (`wrktr_init`, `wrktr_clone`, `wrktr_adopt`). Once a project is created, the actual path is stored in the session config and `WRKTR_REPO_DIR_NAME` is not consulted again.

---

## Config files

Configs live in `~/.config/wrktr/<name>.env`. They are plain `KEY=value` text files — one variable per line, no shell syntax, no `export`. Created with `600` permissions by `wrktr_generate`.

```
# wrktr session config
WRKTR_NAME=myapp
WRKTR_BASE_TRUNK=/Users/you/projects/myapp
WRKTR_BASE_DIR=/Users/you/projects/myapp/.wrktr
WRKTR_REMOTE=origin
WRKTR_MAIN_BRANCH=main
```

`wrktr_use` reads the file with a line-by-line parser — it does not execute the file. This means the config is safe to share (in dotfiles repos, team wikis) without accidentally sharing executable code. Values with spaces are supported.

To edit: `wrktr_config_edit` opens the file in `$EDITOR` and validates after saving. To view without editing: `wrktr_config_show`.

To remove a config:

```bash
rm ~/.config/wrktr/omi.env
```

This does not affect the project files or bare repository.

### Migrating old configs

Configs created before this format change used shell script syntax (`export KEY=value`). These are detected automatically on load and still work — `wrktr_use` sources them as before and prints a migration notice. To migrate, run `wrktr_config_edit` and remove the `export ` prefix from each line.

---

## Quick reference

| Goal | Command |
|------|---------|
| Clone from remote | `wrktr_clone <url>` |
| Convert existing clone | `wrktr_adopt [path]` |
| New local project | `wrktr_init` → `wrktr_generate` → `wrktr_use` |
| Add a remote after init | `wrktr_remote_add <name> <url>` |
| Load a project | `wrktr_use <name>` |
| See all project configs | `wrktr_list` |
| Show loaded config file | `wrktr_config_show` |
| Edit loaded config file | `wrktr_config_edit` |
| See all active worktrees | `wrktr_status` |
| Start a new branch | `wrktr_add <branch>` |
| Check out a remote branch | `wrktr_checkout <branch>` |
| Navigate to a worktree | `wrktr_go <branch>` |
| Keep a branch current | `wrktr_rebase` (from inside worktree) |
| Push a branch | `wrktr_push` (from inside worktree) |
| Remove a branch | `wrktr_remove <branch>` |
| Run git on the bare repo | `wrktr_git <args>` |
| Raw git worktree command | `wrktr <subcommand>` |
| Navigate to trunk | `wrktr_base` |
| Shell prompt context | `wrktr_prompt_info` (embed in PS1) |
| Preview before running | `wrktr_dryrun_enable` → run → `wrktr_dryrun_disable` |
| Remove wrktr from shell | `wrktr_unload` |
| Reload after file edits | `wrktr_reload` |
| All commands | `wrktr_help` |
| Help for one command | `wrktr_help <command>` or `wrktr_<command> --help` |
