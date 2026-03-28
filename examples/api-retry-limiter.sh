#!/bin/bash
# api-retry-limiter.sh — Limit API error retries to prevent token waste
#
# Solves: Claude Code retries API calls on transient errors without
#         backoff, burning tokens on repeated failures.
#         Related to #40376 (rescue from 4xx/5xx) and general cost concerns.
#
# How it works: PostToolUse hook that tracks API error patterns.
#   If the same error appears 3+ times in 60 seconds, warns the user
#   and suggests waiting or switching approaches.
#
# Complements api-error-alert (built-in) with retry-specific logic.
#
# TRIGGER: PostToolUse
# MATCHER: "" (all tools — API errors can come from any tool)

INPUT=$(cat)
ERROR=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null | head -c 500)
[ -z "$ERROR" ] && exit 0

# Only track API-related errors
echo "$ERROR" | grep -qiE "rate.limit|429|500|502|503|529|overloaded|timeout|ECONNREFUSED|ENOTFOUND" || exit 0

ERROR_LOG="/tmp/cc-api-errors-${PPID}"
NOW=$(date +%s)
ERROR_TYPE=$(echo "$ERROR" | grep -oiE "rate.limit|429|500|502|503|529|overloaded|timeout|ECONNREFUSED" | head -1)

echo "$NOW $ERROR_TYPE" >> "$ERROR_LOG"

# Count recent errors of same type
RECENT=$(awk -v now="$NOW" -v type="$ERROR_TYPE" '$1 > now - 60 && $2 == type {count++} END {print count+0}' "$ERROR_LOG")

if [ "$RECENT" -ge 5 ]; then
    echo "⚠ API error loop: ${ERROR_TYPE} occurred ${RECENT} times in 60s" >&2
    echo "  Suggestion: Wait 30-60 seconds before retrying" >&2
    echo "  Or: Switch to a different approach that doesn't require this API" >&2
elif [ "$RECENT" -ge 3 ]; then
    echo "⚠ Repeated API error: ${ERROR_TYPE} (${RECENT}x in 60s)" >&2
fi

exit 0
