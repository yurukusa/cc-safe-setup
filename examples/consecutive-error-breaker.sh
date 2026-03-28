#!/bin/bash
# ================================================================
# consecutive-error-breaker.sh — Stop after N consecutive errors
# ================================================================
# PURPOSE:
#   When Claude Code hits the same error repeatedly (e.g., build
#   failure, test failure, API error), it often keeps retrying
#   the same approach. This hook counts consecutive non-zero
#   exit codes and blocks further tool calls after a threshold.
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"
#
# CONFIGURATION:
#   CC_ERROR_STREAK_MAX=5  (max consecutive errors, default: 5)
#
# See: https://github.com/anthropics/claude-code/issues/38239
# ================================================================

INPUT=$(cat)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // "0"' 2>/dev/null)
STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null)
STDERR=$(echo "$INPUT" | jq -r '.tool_result.stderr // empty' 2>/dev/null)

STATE_FILE="/tmp/cc-error-streak"
MAX_STREAK="${CC_ERROR_STREAK_MAX:-5}"

# Success resets the streak
if [ "$EXIT_CODE" = "0" ]; then
    echo "0" > "$STATE_FILE"
    exit 0
fi

# Increment error streak
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
NEW_STREAK=$((CURRENT + 1))
echo "$NEW_STREAK" > "$STATE_FILE"

if [ "$NEW_STREAK" -ge "$MAX_STREAK" ]; then
    echo "⚠ $NEW_STREAK consecutive errors detected. Claude may be stuck." >&2
    echo "Last exit code: $EXIT_CODE" >&2
    if [ -n "$STDERR" ]; then
        echo "Last error: $(echo "$STDERR" | head -c 200)" >&2
    fi
    echo "Consider: try a different approach, check prerequisites, or ask for help." >&2
    echo "To reset: rm /tmp/cc-error-streak" >&2
fi

exit 0
