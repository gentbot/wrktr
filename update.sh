#!/usr/bin/env bash
# update.sh — pull the latest wrktr and reinstall.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"

printf 'wrktr updater\n\n'

# Pull latest changes
printf 'Pulling latest changes...\n'
git -C "$SCRIPT_DIR" pull

printf '\n'

# Reinstall
"$SCRIPT_DIR/install.sh"

printf '\nTo pick up changes in any open terminal:\n\n'
printf '  wrktr_reload\n\n'
