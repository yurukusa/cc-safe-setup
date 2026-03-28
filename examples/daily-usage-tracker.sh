#!/bin/bash
# ================================================================
# daily-usage-tracker.sh — Track daily tool call count
# ================================================================
# PURPOSE:
#   Records each tool call with a timestamp. At session end (or on
#   demand), shows how many tool calls were made today vs yesterday.
#   Helps detect abnormal usage patterns early.
#
# TRIGGER: PostToolUse
# MATCHER: (any — leave matcher empty)
#
# CONFIGURATION:
#   CC_DAILY_WARN=500   (warn if daily count exceeds this, default: 500)
#
# Output: logs to ~/.claude/daily-usage/YYYY-MM-DD.log
# ================================================================

DAILY_DIR="${HOME}/.claude/daily-usage"
mkdir -p "$DAILY_DIR"

TODAY=$(date +%Y-%m-%d)
TODAY_FILE="${DAILY_DIR}/${TODAY}.log"
WARN_THRESHOLD="${CC_DAILY_WARN:-500}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)

# Record the call
echo "$(date +%H:%M:%S) $TOOL" >> "$TODAY_FILE"

# Count today's calls
TODAY_COUNT=$(wc -l < "$TODAY_FILE" 2>/dev/null || echo 0)

# Warn at milestones
case "$TODAY_COUNT" in
    100|250|500|1000)
        echo "📊 Daily usage: $TODAY_COUNT tool calls today ($TODAY)" >&2
        ;;
esac

# Warn if threshold exceeded
if [ "$TODAY_COUNT" -eq "$WARN_THRESHOLD" ]; then
    YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null)
    YESTERDAY_FILE="${DAILY_DIR}/${YESTERDAY}.log"
    YESTERDAY_COUNT=0
    [ -f "$YESTERDAY_FILE" ] && YESTERDAY_COUNT=$(wc -l < "$YESTERDAY_FILE")
    echo "⚠ Daily usage warning: $TODAY_COUNT calls today (yesterday: $YESTERDAY_COUNT)" >&2
fi

exit 0
