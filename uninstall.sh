#!/usr/bin/env bash
# uninstall.sh — removes the wrktr install and, with your consent, the source
# line from shell profiles.
#
# Usage: uninstall.sh [--yes]
#   --yes   remove the source line from profiles without asking
#
# Without --yes, uninstall.sh asks per profile when run in a terminal, and
# leaves profiles untouched (listing them) when it is not.

set -e

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help)
            printf 'Usage: uninstall.sh [--yes]\n'
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\nUsage: uninstall.sh [--yes]\n' "$arg" >&2
            exit 2
            ;;
    esac
done

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

    if [ "$ASSUME_YES" -ne 1 ]; then
        if [ -t 0 ]; then
            printf 'Remove the wrktr source line from %s? [y/N]: ' "$profile"
            read -r answer
            case "$answer" in
                y|Y|yes|YES) ;;
                *)
                    printf 'Left unchanged: %s\n' "$profile"
                    return
                    ;;
            esac
        else
            printf 'Profile not modified: %s\n' "$profile"
            printf '  Remove the line containing "wrktr/worktree-functions.sh" yourself, or re-run with --yes.\n'
            return
        fi
    fi

    # Rewrite in place (cat >) rather than mv, so a symlinked profile stays a
    # symlink and keeps its permissions. grep -v exits 1 when no lines remain,
    # which is fine here.
    local tmp
    tmp="$(mktemp)"
    grep -vF "wrktr/worktree-functions.sh" "$profile" > "$tmp" || true
    cat "$tmp" > "$profile"
    rm -f "$tmp"
    printf 'Removed source line from: %s\n' "$profile"
}

for profile in "${PROFILES[@]}"; do
    _remove_source_line "$profile"
done

printf '\nUninstallation complete.\n'
printf 'Open a new terminal (or restart your shell) to finish removing wrktr.\n\n'
