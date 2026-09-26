# Changelog

All notable changes to wrktr are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
- **Patch** — bug fixes with no behavior change
- **Minor** — new functions or options; fully backwards-compatible
- **Major** — breaking changes to existing function behavior, config format, or env var names

---

## [Unreleased]

### Added
- Tests: the real `wrktr_remove` path and its branch-delete and force-delete prompts, driven through a pty; `wrktr_init` HEAD and branch-name cases; `wrktr_use` session restore
- Tests: command-level suite in `tests/commands.bats` covering `wrktr_clone`, `add`, `go`, `base`, `status`, `prompt_info`, `update`, `checkout`, `remote_add`, `rebase`, `push`, `remove` (dry-run), `git`, `list`, `current`, `config_show` and dry-run toggling; version-consistency tests (script, CHANGELOG, man page)
- Tests: `wrktr_init` dry-run and stale-temp-dir cases (run in a pty via `tests/helpers/run_in_pty.py`), and zsh source/unload/reload cases

### Changed
- CI: the Linux job installs `mandoc` so the man-page lint test runs there (macOS already has it)
- CI: `actions/checkout` bumped to v7.0.1 (pinned by SHA), which runs on Node 24; the previous pin ran on the deprecated Node 20
- `install.sh` no longer edits your shell profile without consent: it asks first when run in a terminal, and leaves the profile untouched (printing the line to add) when it is not. New flags: `--yes` adds the line without asking, `--no-profile` never touches the profile. `update.sh` passes flags through.
- `uninstall.sh` asks before removing the source line from each profile, and lists the profiles without changing them when not run in a terminal. `--yes` removes the line without asking.
- Sourcing `worktree-functions.sh` is now silent; set `WRKTR_VERBOSE=1` to print the "Worktree functions loaded" banner. Sourcing also returns 0 instead of the exit status of the last command.
- `wrktr_git` in dry-run mode now runs read-only git commands (`log`, `status`, `rev-parse`, branch listing, and so on) and only prints commands that could change the repository.
- `wrktr_adopt` restores every remote of the original clone, not only `origin`, and warns about uncommitted changes and stash entries (which are not carried over) before continuing.
- `wrktr_push` pushes with `-u` so the branch tracks the remote, and only offers `--force-with-lease` after a rejected push; authentication and network failures are reported without a force-push prompt.
- `wrktr_reload` keeps the loaded session, dry-run state, `WRKTR_CONFIG_DIR` and `WRKTR_REPO_DIR_NAME`, and refuses to reload a file that does not parse.
- Documented git requirements corrected: 2.22 or later (`git branch --show-current`), and 2.42 or later for `wrktr_init` (`git worktree add --orphan`)
- CI: the bash 3.2 and 5.x legs now run bats under an explicitly chosen interpreter and assert its version; zsh is installed on Linux so the zsh tests run there; `actions/checkout` is pinned to a commit SHA
- Release workflow: fails if the tag does not match `WRKTR_VERSION` and a CHANGELOG entry

### Fixed
- Docs: in-script `wrktr_help`, the man page and `docs/wrktr.md` now describe current behavior for `wrktr_use` (parses the config, never sources it; a failed load keeps the previous session), `wrktr_push`, `wrktr_adopt`, `wrktr_reload`, `wrktr_git` in dry-run, and the offline fallback of `wrktr_add`/`wrktr_checkout`; the reference no longer says old-format configs are sourced. Man page: replaced the placeholder clone URLs, fixed the `./install.sh` line that was dropped from the rendered page, and set a date that man tools can parse
- `wrktr_use`: when the session being loaded fails validation, the previously loaded session is restored instead of being lost
- `wrktr_init`: the bare repository's `HEAD` now points at the chosen main branch instead of an unborn `master`, so plain git commands in the bare repo work; an invalid branch name is now rejected before anything is created
- `uninstall.sh`: rewrites profiles in place, so a symlinked profile stays a symlink and keeps its permissions, and no longer aborts when the source line was the only line
- `wrktr_add`, `wrktr_checkout`: a failed fetch now falls back to the refs fetched previously instead of aborting, so they work offline when the base ref already exists locally
- `wrktr_status`: detached worktrees are compared from their own HEAD rather than the bare repository's
- `wrktr_clone`: the URL is passed after `--`, so a URL beginning with `-` cannot be read as a git option
- `wrktr_generate`, `wrktr_init`, `wrktr_adopt`: a leading `~` in a typed path is expanded
- `wrktr_adopt`: no longer leaks the `input_branch` global
- `wrktr_init`: if you decline removal of the temporary directory, it now says so and how to remove it, instead of continuing silently
- Docs: README clone URL, `wrktr_dryrun_status` documented, typo in the 1.0.2 entry
- `WRKTR_SOURCE_PATH` / `wrktr_reload`: now resolve the sourced file correctly under zsh (`BASH_SOURCE` is bash-only), so `wrktr_reload` works in zsh
- `wrktr_unload`: no longer depends on `compgen`, which does not exist in zsh; previously functions were left defined after unload
- `wrktr_init`: dry-run mode no longer fails with "Target already exists"; it now reports the planned steps and changes nothing
- `wrktr_init`: the stale `.wrktr-init-tmp` check now runs before `git init --bare`, so an aborted run no longer leaves a `.wrktr` directory behind that blocks every retry
- `wrktr_go`, `wrktr_add`, `wrktr_checkout`, `wrktr_remove`, `wrktr_clone`: a branch name that cannot be converted to a directory name (for example one ending in `-`) now fails with `Invalid branch name` instead of resolving to the trunk directory; `wrktr_go` no longer silently changes into the trunk
- `wrktr_config_edit`: `EDITOR` may now include arguments (for example `code --wait`), and a failing editor is reported instead of printing "Config is valid"
- `wrktr_use`: clears the previous session's variables before loading, so a config without a `WRKTR_REMOTE` line no longer inherits the old remote; only the five session keys (`WRKTR_NAME`, `WRKTR_BASE_TRUNK`, `WRKTR_BASE_DIR`, `WRKTR_REMOTE`, `WRKTR_MAIN_BRANCH`) are read from a config file
- `WRKTR_VERSION` corrected to 1.0.2 to match the released CHANGELOG entry; man page header updated to match

---

## [1.0.2] — 2026-06-23
### Fixed
- `_wrktr_sanitize_branch_name`: Fixed branch naming bug. Previously was adding an arbitrary `%` to the end of the branch and directory name


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
