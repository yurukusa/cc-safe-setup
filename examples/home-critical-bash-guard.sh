#!/bin/bash
# home-critical-bash-guard.sh — Block Bash commands that delete/modify critical home files
#
# Solves: Bash commands that rm/mv/truncate critical dotfiles and directories
#   - #49554: auto mode approved ~/.ssh directory deletion
#   - #49539: ~/.git-credentials PATs deleted without confirmation
#   - #49464: ./~ misinterpreted as ~/ leading to home directory deletion attempt
#
# Complements dotfile-protection-guard.sh (which covers Write/Edit tools).
# This hook covers the Bash tool path — rm, mv, truncate, > redirect on dotfiles.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

HOME_DIR="$HOME"

# Critical paths (regex patterns)
CRITICAL="(${HOME_DIR}|\~)/\.(bashrc|bash_profile|zshrc|zshenv|profile|login|logout|ssh|git-credentials|gitconfig|gnupg|npmrc|netrc|docker|kube|aws)"

# Check for rm/unlink targeting critical paths
if echo "$COMMAND" | grep -qE "(rm|unlink)\s" && echo "$COMMAND" | grep -qE "$CRITICAL"; then
    echo "BLOCKED: Deleting critical home directory file" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Check for mv (rename/move) of critical paths
if echo "$COMMAND" | grep -qE "mv\s" && echo "$COMMAND" | grep -qE "$CRITICAL"; then
    echo "BLOCKED: Moving/renaming critical home directory file" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Check for truncation via redirect (> ~/.bashrc or : > ~/.bashrc)
if echo "$COMMAND" | grep -qE ">\s*(${HOME_DIR}|\~)/\."; then
    TARGET=$(echo "$COMMAND" | grep -oP ">\s*\K(${HOME_DIR}|~)/\.[^\s;|&]+")
    if echo "$TARGET" | grep -qE "$CRITICAL"; then
        echo "BLOCKED: Truncating critical home directory file" >&2
        echo "Command: $COMMAND" >&2
        exit 2
    fi
fi

# Check for chmod on critical credential files
if echo "$COMMAND" | grep -qE "chmod\s.*777" && echo "$COMMAND" | grep -qE "$CRITICAL"; then
    echo "BLOCKED: Removing permissions on critical file" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

exit 0
