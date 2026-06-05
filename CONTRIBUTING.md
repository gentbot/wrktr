# Contributing to wrktr

Thank you for contributing. This document covers the development environment, coding
conventions, how to add a new function, and the pull request process.

---

## Development environment

No build step is required. The entire tool is a single sourced shell file.

**Requirements:**
- bash 3.2 or later
- git
- rsync (for `wrktr_init` tests)
- [bats-core](https://github.com/bats-core/bats-core) (test runner)
- [shellcheck](https://www.shellcheck.net/) (linter)

```bash
# macOS
brew install bats-core shellcheck

# Ubuntu / Debian
sudo apt-get install shellcheck
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core
sudo /tmp/bats-core/install.sh /usr/local
```

---

## Running the tests

```bash
bats tests/
```

To run a single test file:

```bash
bats tests/wrktr.bats
```

To run a specific test by name:

```bash
bats --filter "wrktr_validate" tests/
```

---

## Running the linter

```bash
shellcheck worktree-functions.sh install.sh uninstall.sh
```

Both `shellcheck` and `bats tests/` must pass before submitting a pull request. CI
runs them on ubuntu-latest and macOS (system bash 3.2 and Homebrew bash 5.x).

---

## Coding conventions

### Naming

| Type | Convention | Example |
|------|-----------|---------|
| Public function | `wrktr_<name>` | `wrktr_add` |
| Internal function | `_wrktr_<name>` | `_wrktr_assert_subpath` |
| Internal helper | `_wrktr_<name>` | `_wrktr_is_dryrun`, `_wrktr_run` |
| Environment variable (session) | `WRKTR_<NAME>` | `WRKTR_BASE_DIR` |
| Local variable | lowercase `snake_case` | `local safe_branch` |

Never introduce a function or variable name that doesn't follow this scheme. Public
functions must start with `wrktr_`; everything else must start with `_wrktr_`.

### Docblock format

Every function (public and internal) must have a docblock immediately above its
`function` declaration:

```bash
# -----------------------------------------------------------------------------
# wrktr_example
# -----------------------------------------------------------------------------
# What it does:
#   One paragraph explaining what the function does and any important behavior
#   the caller needs to know about.
#
# Arguments:
#   $1 — description of first argument (include if required)
#   $2 — description of second argument (include if optional: "optional, ...")
#
# Exit codes:
#   0 — success case
#   1 — failure case
#
# Examples:
#   wrktr_example feature/login
# -----------------------------------------------------------------------------
function wrktr_example() {
```

Omit sections that don't apply (e.g. no `Arguments:` section for zero-argument functions).

### Error messages

Use `_wrktr_breaker red "..."` for error output. This writes to stderr.

Use `_wrktr_breaker "..."` (no color) for informational output. This writes to stdout.

Error messages should state what went wrong, not what the user should do:
- **Good:** `_wrktr_breaker red "Session config not found: $config"`
- **Bad:** `_wrktr_breaker red "Please run wrktr_generate first"`

Follow an error message with a hint when the correct action is obvious:
```bash
_wrktr_breaker red "Session config not found: $config"
_wrktr_breaker "To create it: wrktr_generate $session"
```

Do not write multi-line inline strings with `printf` for single-concept messages. Use
`_wrktr_breaker` for each distinct thought.

### Dry-run support

Every function that mutates filesystem state or runs git commands must support dry-run
mode. There are two patterns:

**For external commands:** wrap with `_wrktr_run`:

```bash
if ! _wrktr_run git worktree add "$target" "$branch"; then
    _wrktr_breaker red "Failed to create worktree"
    return 1
fi
```

`_wrktr_run` prints the command when dry-run is enabled and skips execution.

**For conditional logic that branches on dry-run:** use `_wrktr_is_dryrun`:

```bash
if _wrktr_is_dryrun; then
    _wrktr_breaker "[DRY RUN] Would create $target"
    return 0
fi
# ... actual mutation ...
```

Validation still runs in dry-run mode. File writes and git mutations do not.

### Bash 3.2 compatibility

The tool targets bash 3.2 (the macOS default). Do not use:
- `declare -A` (associative arrays)
- `mapfile` / `readarray`
- `${var,,}` / `${var^^}` (case conversion)
- `declare -n` (name references)
- `**` glob
- `[[ str =~ regex ]]` with capture groups (matching is fine, captures are not)

Use `[[ ]]` for string comparisons and pattern matching; use `[ ]` for arithmetic and
file tests. Both work in bash 3.2.

### Validation

Public functions that operate on a loaded session must begin with:

```bash
wrktr_validate || return 1
```

This ensures the function fails cleanly when no session is loaded or the session is
broken, rather than producing confusing git errors.

---

## Adding a new function

Before writing code, consider whether the function:
- Belongs as an option on an existing function (prefer extending)
- Is general enough to be useful to others (avoid one-off commands)
- Needs dry-run support (any function that mutates state: yes)

When adding a new public function, complete this checklist:

- [ ] **Docblock** — immediately above the `function` line, following the format above
- [ ] **`--help` guard** — first line inside the function body:
  ```bash
  [ "$1" = "--help" ] && { wrktr_help <name>; return 0; }
  ```
- [ ] **`wrktr_validate` call** — for session-dependent commands
- [ ] **Dry-run support** — `_wrktr_run` for external commands; `_wrktr_is_dryrun` for branching logic
- [ ] **Error messages to stderr** — use `_wrktr_breaker red "..."` for errors
- [ ] **`wrktr_help` entry** — add a `<name>) cat <<'EOF' ... EOF ;;` case to the `wrktr_help` function
- [ ] **`docs/wrktr.md` entry** — add documentation under the correct section in the Function reference
- [ ] **Quick reference row** — add a row to the Quick reference table in `docs/wrktr.md`
- [ ] **Tests** — add at least one success test and one failure test to `tests/wrktr.bats`
- [ ] **CHANGELOG entry** — add the function to the `[Unreleased]` section in `CHANGELOG.md`
- [ ] **Tab completion** — register the function in the tab completion section if it takes branch names or session names as arguments

---

## Pull request process

1. Fork the repository and create a branch from `main`
2. Make your change following the conventions above
3. Confirm `bats tests/` passes
4. Confirm `shellcheck worktree-functions.sh` passes
5. Open a pull request against `main`

Pull request descriptions should explain the motivation, not just restate the diff. If
the change fixes a bug, describe the bug. If it adds a function, explain the use case.

For non-trivial changes, open an issue first to discuss the approach before investing
time in implementation.

---

## Reporting bugs

Use the GitHub issue tracker. Include:
- What you ran
- What you expected
- What happened instead
- Your `WRKTR_VERSION` (run `echo $WRKTR_VERSION` after sourcing)
- Your shell and OS (`bash --version`, `uname -sr`)

---

## Code of conduct

Be constructive. Disagreement about implementation details is fine; personal hostility
is not. The maintainers reserve the right to close issues or PRs that are not
constructive.
