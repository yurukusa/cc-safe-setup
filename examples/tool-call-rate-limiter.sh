#!/bin/bash
# ================================================================
# tool-call-rate-limiter.sh — Prevent runaway tool calls
# ================================================================
# PURPOSE:
#   Detects when Claude Code is making tool calls too rapidly,
#   which usually indicates a stuck loop or runaway behavior
#   that will burn through your quota.
#
# TRIGGER: PreToolUse
# MATCHER: (any — leave matcher empty to catch all tools)
#
# CONFIGURATION:
#   CC_RATE_LIMIT_MAX=30     (max calls per window, default: 30)
#   CC_RATE_LIMIT_WINDOW=60  (window in seconds, default: 60)
#
# See: https://github.com/anthropics/claude-code/issues/38335
# See: https://github.com/anthropics/claude-code/issues/37917
# ================================================================

RATE_FILE="${HOME}/.claude/rate-limiter.log"
MAX_CALLS="${CC_RATE_LIMIT_MAX:-30}"
WINDOW="${CC_RATE_LIMIT_WINDOW:-60}"

mkdir -p "$(dirname "$RATE_FILE")"

NOW=$(date +%s)
CUTOFF=$((NOW - WINDOW))

# Append current timestamp
echo "$NOW" >> "$RATE_FILE"

# Count calls within window
RECENT=$(awk -v cutoff="$CUTOFF" '$1 >= cutoff' "$RATE_FILE" 2>/dev/null | wc -l)

# Prune old entries (keep file small)
awk -v cutoff="$CUTOFF" '$1 >= cutoff' "$RATE_FILE" > "${RATE_FILE}.tmp" 2>/dev/null
mv "${RATE_FILE}.tmp" "$RATE_FILE" 2>/dev/null

if [ "$RECENT" -gt "$MAX_CALLS" ]; then
    echo "BLOCKED: Rate limit exceeded — $RECENT tool calls in ${WINDOW}s (max: $MAX_CALLS)." >&2
    echo "This usually means Claude is stuck in a loop. Check the task." >&2
    echo "Set CC_RATE_LIMIT_MAX to adjust (current: $MAX_CALLS calls/${WINDOW}s)." >&2
    exit 2
fi

exit 0
