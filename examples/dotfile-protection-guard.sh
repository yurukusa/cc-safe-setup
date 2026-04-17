#!/bin/bash
# dotfile-protection-guard.sh — Block writes to critical dotfiles
#
# Solves: Claude Code modifying or truncating critical user dotfiles
#   - #49615: Installer auto-update zeroed ~/.bash_profile and ~/.zshrc
#   - #49539: ~/.git-credentials PATs deleted without confirmation
#   - #49554: auto mode approved ~/.ssh deletion
#
# What it blocks (Write/Edit tool):
#   ~/.bash_profile, ~/.bashrc, ~/.zshrc, ~/.profile
#   ~/.ssh/*, ~/.git-credentials, ~/.gitconfig
#   ~/.gnupg/*, ~/.npmrc (may contain auth tokens)
#   ~/.aws/credentials, ~/.config/gh/hosts.yml
#
# What it allows:
#   Files in project directories (not under ~/ root)
#   ~/.claude/* (Claude Code's own config)
#
# TRIGGER: PreToolUse  MATCHER: "Write|Edit"

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Expand ~ to actual home directory
HOME_DIR="$HOME"
RESOLVED=$(echo "$FILE" | sed "s|^~|$HOME_DIR|")

# Allow Claude Code's own config
if echo "$RESOLVED" | grep -qE "^${HOME_DIR}/\.claude(/|$)"; then
    exit 0
fi

# Critical dotfiles — block any modification
CRITICAL_PATTERNS=(
    "^${HOME_DIR}/\.(bash_profile|bashrc|zshrc|zshenv|profile|login|logout)$"
    "^${HOME_DIR}/\.ssh(/|$)"
    "^${HOME_DIR}/\.git-credentials$"
    "^${HOME_DIR}/\.gitconfig$"
    "^${HOME_DIR}/\.gnupg(/|$)"
    "^${HOME_DIR}/\.npmrc$"
    "^${HOME_DIR}/\.aws/(credentials|config)$"
    "^${HOME_DIR}/\.config/gh/hosts\.yml$"
    "^${HOME_DIR}/\.netrc$"
    "^${HOME_DIR}/\.docker/config\.json$"
    "^${HOME_DIR}/\.kube/config$"
)

for PATTERN in "${CRITICAL_PATTERNS[@]}"; do
    if echo "$RESOLVED" | grep -qE "$PATTERN"; then
        echo "BLOCKED: Modifying critical dotfile: $FILE" >&2
        echo "This file contains shell config or credentials that should not be altered by AI." >&2
        echo "If you need to modify this file, do it manually." >&2
        exit 2
    fi
done

exit 0
