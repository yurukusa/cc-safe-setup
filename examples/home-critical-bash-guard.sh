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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-home-critical-bash-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [home-critical-bash-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
    # -P は GNU 拡張。BSD grep では TARGET が空になり、下の「重要な設定ファイルを切り詰める」
    # 検査だけが静かに消える。\K の代わりに > から一致させて前置きを落とす。
    TARGET=$(echo "$COMMAND" \
        | grep -oE ">[[:space:]]*(${HOME_DIR}|~)/\.[^[:space:];|&]+" \
        | sed -E 's/^>[[:space:]]*//')
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
