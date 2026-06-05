#!/usr/bin/env bash
# uninstall.sh — removes the wrktr install and source line from shell profiles.

set -e

INSTALL_DIR="$HOME/.local/lib/wrktr"
INSTALL_FILE="$INSTALL_DIR/worktree-functions.sh"
MAN_FILE="$HOME/.local/share/man/man1/wrktr.1"

PROFILES=(
    "$HOME/.zshrc"
    "$HOME/.bash_profile"
    "$HOME/.bashrc"
    "$HOME/.profile"
)

printf 'wrktr uninstaller\n\n'

# ---------------------------------------------------------------------------
# Remove installed file
# ---------------------------------------------------------------------------

if [ -f "$INSTALL_FILE" ]; then
    rm "$INSTALL_FILE"
    printf 'Removed: %s\n' "$INSTALL_FILE"
else
    printf 'File not found (already removed?): %s\n' "$INSTALL_FILE"
fi

# Remove directory if empty
if [ -d "$INSTALL_DIR" ] && [ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    rmdir "$INSTALL_DIR"
    printf 'Removed directory: %s\n' "$INSTALL_DIR"
fi

# Remove man page
if [ -f "$MAN_FILE" ]; then
    rm "$MAN_FILE"
    printf 'Removed man page: %s\n' "$MAN_FILE"
fi

# ---------------------------------------------------------------------------
# Remove source line from shell profiles
# ---------------------------------------------------------------------------

_remove_source_line() {
    local profile="$1"
    if [ ! -f "$profile" ]; then
        return
    fi
    if ! grep -qF "wrktr/worktree-functions.sh" "$profile" 2>/dev/null; then
        return
    fi

    local tmp
    tmp="$(mktemp)"
    grep -vF "wrktr/worktree-functions.sh" "$profile" > "$tmp"
    mv "$tmp" "$profile"
    printf 'Removed source line from: %s\n' "$profile"
}

for profile in "${PROFILES[@]}"; do
    _remove_source_line "$profile"
done

printf '\nUninstallation complete.\n'
printf 'Open a new terminal (or restart your shell) to finish removing wrktr.\n\n'
