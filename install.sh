#!/usr/bin/env bash
# install.sh — installs wrktr into ~/.local/lib/wrktr and adds a source line
# to the detected shell profile.

set -e

INSTALL_DIR="$HOME/.local/lib/wrktr"
INSTALL_FILE="$INSTALL_DIR/worktree-functions.sh"
MAN_DIR="$HOME/.local/share/man/man1"
MAN_FILE="$MAN_DIR/wrktr.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
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
else
    # Append source line
    printf '\n%s\n' "$SOURCE_LINE" >> "$PROFILE"
    printf 'Added source line to: %s\n' "$PROFILE"
fi

printf '\nInstallation complete.\n'
printf 'Reload your shell profile to start using wrktr:\n\n'
printf '  source %s\n\n' "$PROFILE"
