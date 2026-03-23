#!/bin/bash
# verify-before-commit.sh — Block git commit unless tests passed recently
#
# Solves: Claude saying "fixed" and committing without actually
# verifying the fix works (#37818, #36970)
#
# How it works:
# 1. Your test runner creates a marker file on success
# 2. This hook checks for the marker before allowing commit
# 3. Marker expires after 10 minutes (stale test results don't count)
#
# Marker creation (add to your test script or PostToolUse hook):
#   touch "/tmp/cc-tests-passed-$(pwd | md5sum | cut -c1-8)"
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/verify-before-commit.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
    exit 0
fi

# Must be in a git repo
git rev-parse --git-dir &>/dev/null || exit 0

# Check for test marker (created by test runner)
PROJECT_HASH=$(pwd | md5sum | cut -c1-8)
MARKER="/tmp/cc-tests-passed-${PROJECT_HASH}"
MAX_AGE=600  # 10 minutes

if [ ! -f "$MARKER" ]; then
    echo "BLOCKED: No test evidence found. Run tests before committing." >&2
    echo "" >&2
    echo "Your test runner should create: $MARKER" >&2
    echo "Example: pytest && touch $MARKER" >&2
    exit 2
fi

# Check marker age
MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$MARKER" 2>/dev/null || echo 0) ))
if (( MARKER_AGE > MAX_AGE )); then
    echo "BLOCKED: Test results are stale (${MARKER_AGE}s old, max ${MAX_AGE}s)." >&2
    echo "Run tests again before committing." >&2
    exit 2
fi

exit 0
