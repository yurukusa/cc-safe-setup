#!/bin/bash
# consecutive-failure-circuit-breaker.sh — Stop after repeated failures
#
# Solves: Claude escalating to destructive actions after repeated failures (#31946).
#         Without this, Claude retries failing commands dozens of times,
#         eventually trying increasingly dangerous alternatives.
#
# How it works: PostToolUse hook on Bash that tracks consecutive non-zero
#   exit codes. After CC_MAX_CONSECUTIVE_FAILURES (default 3), blocks
#   further Bash calls until a success resets the counter.
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0

EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exitCode // "0"' 2>/dev/null)
MAX_FAILURES="${CC_MAX_CONSECUTIVE_FAILURES:-3}"
COUNTER_FILE="/tmp/claude-consecutive-failures-${PPID:-0}"

if [ "$EXIT_CODE" = "0" ]; then
  # Success — reset counter
  echo "0" > "$COUNTER_FILE"
  exit 0
fi

# Failure — increment counter
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

if [ "$COUNT" -ge "$MAX_FAILURES" ]; then
  echo "CIRCUIT BREAKER: $COUNT consecutive Bash failures detected." >&2
  echo "" >&2
  echo "Stop and reassess your approach. Repeated failures often lead to" >&2
  echo "increasingly risky workarounds. Consider:" >&2
  echo "  1. Read the error messages carefully" >&2
  echo "  2. Check your assumptions" >&2
  echo "  3. Try a completely different approach" >&2
  echo "  4. Ask the user for help" >&2
  # Don't block (exit 0) — just warn strongly via stderr
  # PostToolUse can't block, but the warning enters context
fi

exit 0
