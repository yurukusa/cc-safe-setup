#!/bin/bash
# git-index-lock-cleanup.sh — Remove stale .git/index.lock after git commands
#
# Solves: Claude Code leaves .git/index.lock behind after git operations,
#         blocking subsequent git commands from other tools (IDEs, manual CLI).
#         Reported in #28546 (Windows) and #11005 (Linux/macOS).
#
# How it works: PostToolUse hook on Bash. After any git command,
#               checks if .git/index.lock exists and no git process
#               is running. If stale, removes it.
#
# TRIGGER: PostToolUse  MATCHER: "Bash"
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only check after git commands
echo "$COMMAND" | grep -qE '\bgit\b' || exit 0

# Find git root
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
LOCK="$GIT_DIR/index.lock"

# Check if lock file exists
[ -f "$LOCK" ] || exit 0

# Check if any git process is still running
if pgrep -x git > /dev/null 2>&1; then
    # Git is running — lock is legitimate
    exit 0
fi

# Stale lock detected — remove it
rm -f "$LOCK" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "INFO: Removed stale .git/index.lock (no git process running)" >&2
fi

exit 0
