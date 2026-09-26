#!/usr/bin/env bash
# install.sh — installs wrktr into ~/.local/lib/wrktr and, with your consent,
# adds a source line to the detected shell profile.
#
# Usage: install.sh [--yes] [--no-profile]
#   --yes          add the source line to the profile without asking
#   --no-profile   never touch the profile; just print the line to add
#
# Without either flag, install.sh asks before editing the profile when run in
# a terminal, and leaves the profile untouched when it is not.

set -e

ASSUME_YES=0
NO_PROFILE=0
for arg in "$@"; do
    case "$arg" in
        --yes|-y)     ASSUME_YES=1 ;;
        --no-profile) NO_PROFILE=1 ;;
        -h|--help)
            printf 'Usage: install.sh [--yes] [--no-profile]\n'
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\nUsage: install.sh [--yes] [--no-profile]\n' "$arg" >&2
            exit 2
            ;;
    esac
done

INSTALL_DIR="$HOME/.local/lib/wrktr"
INSTALL_FILE="$INSTALL_DIR/worktree-functions.sh"
MAN_DIR="$HOME/.local/share/man/man1"
MAN_FILE="$MAN_DIR/wrktr.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
if [ -z "$SCRIPT_DIR" ]; then
    printf 'Error: cannot resolve script directory\n' >&2
    exit 1
fi
SOURCE_FILE="$SCRIPT_DIR/worktree-functions.sh"
SOURCE_MAN="$SCRIPT_DIR/docs/wrktr.1"

# ---------------------------------------------------------------------------
# Detect shell profile
# ---------------------------------------------------------------------------

_detect_profile() {
    local shell_name
    shell_name="$(basename "$SHELL" 2>/dev/null || printf '')"

    case "$shell_name" in
        zsh)
            printf '%s/.zshrc' "$HOME"
            ;;
        bash)
            if [ "$(uname -s)" = "Darwin" ]; then
                if [ -f "$HOME/.bash_profile" ]; then
                    printf '%s/.bash_profile' "$HOME"
                else
                    printf '%s/.bashrc' "$HOME"
                fi
            else
                printf '%s/.bashrc' "$HOME"
            fi
            ;;
        *)
            # Unknown shell — let the user handle it manually
            printf ''
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

printf 'wrktr installer\n\n'

# Check source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    printf 'Error: cannot find worktree-functions.sh at:\n  %s\n' "$SOURCE_FILE" >&2
    printf 'Run install.sh from the wrktr repository directory.\n' >&2
    exit 1
fi

# Create install directory
if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
fi

# Copy the functions file
cp "$SOURCE_FILE" "$INSTALL_FILE"
printf 'Installed: %s\n' "$INSTALL_FILE"

# Install man page if present
if [ -f "$SOURCE_MAN" ]; then
    mkdir -p "$MAN_DIR"
    cp "$SOURCE_MAN" "$MAN_FILE"
    printf 'Installed man page: %s\n' "$MAN_FILE"
    # Update man index if mandb or makewhatis is available
    if command -v mandb >/dev/null 2>&1; then
        mandb -q 2>/dev/null || true
    elif command -v makewhatis >/dev/null 2>&1; then
        makewhatis "$MAN_DIR" 2>/dev/null || true
    fi
fi

# Build the source line
SOURCE_LINE="source \"\$HOME/.local/lib/wrktr/worktree-functions.sh\""

# Detect profile
PROFILE="$(_detect_profile)"

if [ -z "$PROFILE" ]; then
    printf '\nCould not detect shell profile automatically.\n'
    printf 'Add the following line to your shell profile manually:\n\n'
    printf '  %s\n\n' "$SOURCE_LINE"
    exit 0
fi

# Check if already present
if [ -f "$PROFILE" ] && grep -qF "wrktr/worktree-functions.sh" "$PROFILE" 2>/dev/null; then
    printf '\nSource line already present in %s — no changes made.\n' "$PROFILE"
    printf '\nInstallation complete.\n'
    exit 0
fi

# Editing a shell profile needs consent: --yes, or an explicit answer at a prompt.
add_line=0
if [ "$NO_PROFILE" -eq 1 ]; then
    add_line=0
elif [ "$ASSUME_YES" -eq 1 ]; then
    add_line=1
elif [ -t 0 ]; then
    printf '\nAdd this line to %s so wrktr loads in new shells?\n\n  %s\n\n[y/N]: ' "$PROFILE" "$SOURCE_LINE"
    read -r answer
    case "$answer" in
        y|Y|yes|YES) add_line=1 ;;
    esac
fi

if [ "$add_line" -eq 1 ]; then
    printf '\n%s\n' "$SOURCE_LINE" >> "$PROFILE"
    printf 'Added source line to: %s\n' "$PROFILE"
    printf '\nInstallation complete.\n'
    printf 'Reload your shell profile to start using wrktr:\n\n'
    printf '  source %s\n\n' "$PROFILE"
else
    printf '\nShell profile not modified: %s\n' "$PROFILE"
    printf 'To load wrktr in new shells, add this line yourself (or re-run with --yes):\n\n'
    printf '  %s\n\n' "$SOURCE_LINE"
    printf 'Installation complete.\n'
fi
