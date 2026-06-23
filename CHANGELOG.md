# Changelog

All notable changes to wrktr are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
- **Patch** — bug fixes with no behavior change
- **Minor** — new functions or options; fully backwards-compatible
- **Major** — breaking changes to existing function behavior, config format, or env var names

---

## [Unreleased]

---

## [1.0.2] — 2026-06-23
### Fixed
- `_wrktr_sanitize_branch_name`: Fixed branch naming bug. Previously was adding an arbitrary `%` to the end of the branch and riectory name


## [1.0.1] — 2026-06-05

### Fixed
- `wrktr_use`: removed the legacy `source "$config"` path; old-format configs with `export ` prefixes are now parsed safely by the KEY=value parser (strips the prefix, never executes the file as shell code)
- `wrktr_remove`: PWD check now resolves both the current directory and the target path with `pwd -P`, preventing bypass via symlinks or systems where `$TMPDIR` itself is a symlink (e.g. `/tmp` → `/private/tmp` on macOS)
- `wrktr_clone`: initial worktree directory now uses the detected main branch name instead of the hardcoded string `"main"`
- `_wrktr_remote_branches`: replaced `sed` with shell parameter expansion to avoid metacharacter injection when remote names contain special characters; `wrktr_checkout` listing uses `grep -F` for the same reason
- `wrktr_unload`: now unsets `WRKTR_VERSION` along with all other `WRKTR_*` variables
- `wrktr_clone`, `wrktr_adopt`: print a message before any `rm -rf` cleanup so the operation is visible
- `install.sh`: validate `SCRIPT_DIR` immediately after assignment and exit with an error if it could not be resolved
- `wrktr_init`, `wrktr_generate`, `wrktr_adopt`: fail early with a clear error when stdin is not a terminal, preventing hangs in non-interactive environments (CI, piped scripts)

### Removed
- Homebrew formula (`Formula/wrktr.rb`) — distribution via a personal tap is not planned

### Added
- README: explicit platform note that wrktr requires macOS or Linux (Windows needs WSL)
- Tests: coverage for old-format config loading, symlink-based worktree removal guard, `wrktr_unload` variable cleanup, and non-interactive stdin guards

---

## [1.0.0] — 2024

Initial release.

### Added

**Setup**
- `wrktr_clone <url> [destination]` — bare-clone a remote repository into the wrktr structure; detects main branch, creates initial worktree, prints `wrktr_generate` values
- `wrktr_adopt [path]` — convert an existing normal git clone to a wrktr bare structure; original clone is untouched
- `wrktr_init` — initialize a bare repository from an existing local project directory (for new projects with no remote)
- `wrktr_generate [name]` — interactively create a session config at `~/.config/wrktr/<name>.env`
- `wrktr_remote_add <name> <url>` — add a remote to the loaded session's bare repository with the correct fetch refspec

**Session management**
- `wrktr_use <name>` — load a project config into the current shell; validates on load; unsets all vars on failure
- `wrktr_list` — list all available session configs in `~/.config/wrktr/`
- `wrktr_current` — show the loaded session's configuration values
- `wrktr_config_show` — display the path and raw contents of the loaded session config file
- `wrktr_config_edit` — open the session config in `$EDITOR` and run `wrktr_validate` after saving
- `wrktr_validate` — validate the currently-loaded session (runs automatically before most mutating commands)
- `wrktr_status` — show all active worktrees with branch name, ahead/behind count, and dirty state

**Daily operations**
- `wrktr_add <branch> [base-ref]` — create a new branch and worktree directory, then `cd` into it
- `wrktr_checkout <branch>` — fetch a remote branch and create a local worktree for it
- `wrktr_go [branch]` — navigate to a worktree by branch name; handles percent-encoding automatically
- `wrktr_base` — navigate to the trunk directory
- `wrktr_update` — fetch from the configured remote without touching any worktree
- `wrktr_rebase` — fetch and rebase the current branch onto the latest main
- `wrktr_push` — push the current branch; prompts before `--force-with-lease` if rejected
- `wrktr_remove <branch>` — remove a worktree and optionally delete the branch ref

**Git access**
- `wrktr_git <args>` — run any git command against the bare database (auto-supplies `--git-dir`)
- `wrktr <subcommand>` — raw passthrough to `git worktree` via the bare database

**Dry-run mode**
- `wrktr_dryrun_enable` — enable dry-run: print all mutating commands without executing them
- `wrktr_dryrun_disable` — disable dry-run mode
- `wrktr_dryrun_status` — show whether dry-run is currently active

**Help**
- `wrktr_help [command]` — show all commands, or full documentation for one command
- Every command accepts `--help` as its first argument

**Lifecycle**
- `wrktr_unload` — remove all wrktr functions and `WRKTR_*` variables from the current shell
- `wrktr_reload` — unload and re-source from the original path (for picking up file edits)
- `wrktr_prompt_info` — output a context string for embedding in `PS1`

### Design notes

- **Bare repository structure** — the git database lives in `<trunk>/.wrktr` with no working tree of its own; all branch checkouts are equal linked worktrees
- **Branch encoding** — `/` in branch names is percent-encoded as `%2F`; `%` is encoded as `%25` first to avoid double-encoding
- **Config format** — session configs are plain `KEY=value` text files, never executed; `wrktr_use` uses a line-by-line parser
- **`WRKTR_REPO_DIR_NAME`** — the bare repository directory name (default `.wrktr`) is configurable via environment variable; set before sourcing to override
- **`WRKTR_VERSION`** — version string exported on source; follows semver
- **Deletion safety** — all `rm -rf` operations resolve paths to real absolute paths and require explicit confirmation before removing
- **Shell-scoped sessions** — each shell manages its own session independently; no shared state between terminals

---

[Unreleased]: https://github.com/your-username/wrktr/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/your-username/wrktr/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/your-username/wrktr/releases/tag/v1.0.0
