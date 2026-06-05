## What and why

<!-- Explain the motivation. For a bug fix: describe the bug. For a new function: describe the use case. -->

## Changes

<!-- Summary of what changed. -->

## Checklist

### All PRs
- [ ] `bats tests/` passes locally
- [ ] `shellcheck worktree-functions.sh` passes locally
- [ ] `CHANGELOG.md` updated (add entry under `[Unreleased]`)

### New public functions
- [ ] Docblock above function follows the project format
- [ ] `[ "$1" = "--help" ] && { wrktr_help <name>; return 0; }` guard present
- [ ] `wrktr_validate || return 1` at top (for session-dependent functions)
- [ ] Dry-run support: `_wrktr_run` wraps mutations; `_wrktr_is_dryrun` gates conditional logic
- [ ] Error messages use `_wrktr_breaker red "..."` (writes to stderr)
- [ ] Help entry added to `wrktr_help` case statement
- [ ] Documentation added to `docs/wrktr.md` function reference
- [ ] Row added to Quick reference table in `docs/wrktr.md`
- [ ] Tab completion registered if function takes branch or session names
- [ ] Tests added to `tests/wrktr.bats` (at least one success, one failure)

### Behavior changes to existing functions
- [ ] Describe whether the change is backwards-compatible
- [ ] Existing tests updated to reflect new behavior
- [ ] `docs/wrktr.md` updated if command usage or behavior description changed
