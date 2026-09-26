#!/usr/bin/env bats
# Tests for install.sh / uninstall.sh.
#
# Every test runs with HOME pointed at a temporary directory, so nothing
# outside BATS_TEST_TMPDIR is read or written.
#
# Run:  bats tests/installers.bats

REPO="$BATS_TEST_DIRNAME/.."
LINE_MARKER="wrktr/worktree-functions.sh"

setup() {
    local base="${BATS_TEST_TMPDIR:-$BATS_TMPDIR/wrktr-inst-$$-$BATS_TEST_NUMBER}"
    mkdir -p "$base"
    T="$(cd "$base" && pwd -P)"
    export T
    export TEST_HOME="$T/home"
    mkdir -p "$TEST_HOME"
    export TEST_SHELL=/bin/zsh
}

teardown() {
    [ -n "${BATS_TEST_TMPDIR:-}" ] || rm -rf "$T"
}

# Run a script non-interactively (stdin is not a terminal).
_run_script() {
    run env HOME="$TEST_HOME" SHELL="$TEST_SHELL" bash "$REPO/$1" "${@:2}" </dev/null
}

# Run a script inside a pty and type $2 at it.
_run_script_tty() {
    command -v python3 >/dev/null 2>&1 || skip "python3 not available"
    run python3 "$REPO/tests/helpers/run_in_pty.py" \
        "HOME='$TEST_HOME' SHELL='$TEST_SHELL' bash '$REPO/$1' $3" "$2"
}

_profile_lines() {
    grep -cF "$LINE_MARKER" "$TEST_HOME/.zshrc" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# install.sh
# ---------------------------------------------------------------------------

@test "install.sh: installs the file but leaves the profile alone when non-interactive" {
    printf 'export FOO=1\n' > "$TEST_HOME/.zshrc"
    _run_script install.sh
    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/.local/lib/wrktr/worktree-functions.sh" ]
    [ "$(cat "$TEST_HOME/.zshrc")" = "export FOO=1" ]
    [[ "$output" == *"not modified"* ]]
    [[ "$output" == *"source"* ]]
}

@test "install.sh: --yes appends the source line exactly once" {
    printf 'export FOO=1\n' > "$TEST_HOME/.zshrc"
    _run_script install.sh --yes
    [ "$status" -eq 0 ]
    [ "$(_profile_lines)" -eq 1 ]
    _run_script install.sh --yes
    [ "$status" -eq 0 ]
    [ "$(_profile_lines)" -eq 1 ]
    grep -q '^export FOO=1$' "$TEST_HOME/.zshrc"
}

@test "install.sh: --no-profile never touches the profile, even with --yes" {
    printf 'export FOO=1\n' > "$TEST_HOME/.zshrc"
    _run_script install.sh --yes --no-profile
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_HOME/.zshrc")" = "export FOO=1" ]
}

@test "install.sh: rejects an unknown option" {
    _run_script install.sh --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "install.sh: asks first when interactive and does nothing on 'n'" {
    printf 'export FOO=1\n' > "$TEST_HOME/.zshrc"
    _run_script_tty install.sh $'n\n'
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_HOME/.zshrc")" = "export FOO=1" ]
}

@test "install.sh: appends the line when interactive and the answer is 'y'" {
    printf 'export FOO=1\n' > "$TEST_HOME/.zshrc"
    _run_script_tty install.sh $'y\n'
    [ "$status" -eq 0 ]
    [ "$(_profile_lines)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# uninstall.sh
# ---------------------------------------------------------------------------

_install_with_profile() {
    printf 'export FOO=1\nsource "$HOME/.local/lib/wrktr/worktree-functions.sh"\nexport BAR=2\n' \
        > "$TEST_HOME/.zshrc"
    mkdir -p "$TEST_HOME/.local/lib/wrktr"
    cp "$REPO/worktree-functions.sh" "$TEST_HOME/.local/lib/wrktr/"
}

@test "uninstall.sh: leaves profiles alone when non-interactive without --yes" {
    _install_with_profile
    _run_script uninstall.sh
    [ "$status" -eq 0 ]
    [ "$(_profile_lines)" -eq 1 ]
    [[ "$output" == *"$TEST_HOME/.zshrc"* ]]
    [ ! -f "$TEST_HOME/.local/lib/wrktr/worktree-functions.sh" ]
}

@test "uninstall.sh: --yes removes only the source line" {
    _install_with_profile
    _run_script uninstall.sh --yes
    [ "$status" -eq 0 ]
    [ "$(_profile_lines)" -eq 0 ]
    [ "$(cat "$TEST_HOME/.zshrc")" = "$(printf 'export FOO=1\nexport BAR=2')" ]
}

@test "uninstall.sh: --yes keeps a symlinked profile a symlink and preserves its mode" {
    _install_with_profile
    mkdir -p "$T/dotfiles"
    mv "$TEST_HOME/.zshrc" "$T/dotfiles/zshrc"
    chmod 644 "$T/dotfiles/zshrc"
    ln -s "$T/dotfiles/zshrc" "$TEST_HOME/.zshrc"
    _run_script uninstall.sh --yes
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.zshrc" ]
    [ "$(grep -cF "$LINE_MARKER" "$T/dotfiles/zshrc" || true)" -eq 0 ]
    grep -q '^export FOO=1$' "$T/dotfiles/zshrc"
    # ls -l is portable; stat's flags differ between BSD/macOS and GNU/Linux.
    [ "$(ls -l "$T/dotfiles/zshrc" | cut -c1-10)" = "-rw-r--r--" ]
}

@test "uninstall.sh: --yes succeeds when the source line is the only line" {
    mkdir -p "$TEST_HOME/.local/lib/wrktr"
    printf 'source "$HOME/.local/lib/wrktr/worktree-functions.sh"\n' > "$TEST_HOME/.zshrc"
    _run_script uninstall.sh --yes
    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/.zshrc" ]
    [ ! -s "$TEST_HOME/.zshrc" ]
}

@test "uninstall.sh: asks first when interactive and does nothing on 'n'" {
    _install_with_profile
    _run_script_tty uninstall.sh $'n\n'
    [ "$status" -eq 0 ]
    [ "$(_profile_lines)" -eq 1 ]
}

@test "uninstall.sh: removes the line when interactive and the answer is 'y'" {
    _install_with_profile
    _run_script_tty uninstall.sh $'y\n'
    [ "$status" -eq 0 ]
    [ "$(_profile_lines)" -eq 0 ]
}
