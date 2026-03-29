#!/bin/bash
# ================================================================
# session-error-rate-monitor.sh — Detect session quality degradation
# ================================================================
# PURPOSE:
#   Long sessions (6+ hours) show quality decay: more errors,
#   ignored instructions, and destructive actions. This hook
#   tracks the error rate over a rolling window and warns when
#   it exceeds a threshold, suggesting a session restart.
#
# How it works:
#   - Counts tool calls and errors (exit code != 0) in a state file
#   - Calculates error rate over last N tool calls
#   - Warns (stderr) when error rate exceeds threshold
#   - Does NOT block — purely advisory (exit 0 always)
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"
#
# CONFIG:
#   CC_ERROR_RATE_WINDOW=20  (rolling window size)
#   CC_ERROR_RATE_THRESHOLD=40  (% error rate to trigger warning)
#
# See: https://github.com/anthropics/claude-code/issues/32963
# ================================================================

INPUT=$(cat)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // "0"' 2>/dev/null)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only track Bash tool calls
[[ "$TOOL" != "Bash" ]] && exit 0

WINDOW=${CC_ERROR_RATE_WINDOW:-20}
THRESHOLD=${CC_ERROR_RATE_THRESHOLD:-40}
STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/error-rate-history.log"

# Record result: 0=success, 1=error
if [ "$EXIT_CODE" = "0" ]; then
    echo "0" >> "$STATE_FILE"
else
    echo "1" >> "$STATE_FILE"
fi

# Keep only last N entries
TOTAL=$(wc -l < "$STATE_FILE" 2>/dev/null || echo "0")
if [ "$TOTAL" -gt "$WINDOW" ]; then
    tail -n "$WINDOW" "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
fi

# Calculate error rate
if [ "$TOTAL" -ge "$WINDOW" ]; then
    ERRORS=$(tail -n "$WINDOW" "$STATE_FILE" | grep -c "^1$" || echo "0")
    RATE=$(( ERRORS * 100 / WINDOW ))

    if [ "$RATE" -ge "$THRESHOLD" ]; then
        echo "⚠ Session quality alert: ${RATE}% error rate over last ${WINDOW} commands (threshold: ${THRESHOLD}%)" >&2
        echo "  Consider: /compact or starting a fresh session" >&2
    fi
fi

exit 0
