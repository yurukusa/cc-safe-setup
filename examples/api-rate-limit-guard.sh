#!/bin/bash
# ================================================================
# api-rate-limit-guard.sh — Throttle rapid API calls to prevent rate limiting
# ================================================================
# PURPOSE:
#   Claude often makes rapid successive curl/API calls that trigger
#   rate limits (429 Too Many Requests). This hook tracks the last
#   call time and enforces a minimum interval between API requests.
#
#   Default: 1 second between curl/wget/httpie calls.
#   Customize MIN_INTERVAL_MS for your API's rate limit.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(curl *)",
#         "command": "~/.claude/hooks/api-rate-limit-guard.sh"
#       }]
#     }]
#   }
# }
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-api-rate-limit-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [api-rate-limit-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check HTTP client commands
echo "$COMMAND" | grep -qE '^\s*(curl|wget|http|https)\s' || exit 0

# Configurable minimum interval (milliseconds)
MIN_INTERVAL_MS="${CC_API_RATE_LIMIT_MS:-1000}"

TIMESTAMP_FILE="/tmp/.cc-api-rate-limit-$$"
NOW_MS=$(date +%s%N | cut -b1-13 2>/dev/null || date +%s)

if [ -f "$TIMESTAMP_FILE" ]; then
    LAST_MS=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0")
    DIFF=$((NOW_MS - LAST_MS))
    if [ "$DIFF" -lt "$MIN_INTERVAL_MS" ] 2>/dev/null; then
        WAIT=$((MIN_INTERVAL_MS - DIFF))
        echo "⚠ Rate limit guard: ${WAIT}ms cooldown remaining." >&2
        echo "  Set CC_API_RATE_LIMIT_MS to adjust (current: ${MIN_INTERVAL_MS}ms)." >&2
        # Note: exit 0 = warn only. Change to exit 2 to hard-block.
    fi
fi

echo "$NOW_MS" > "$TIMESTAMP_FILE"
exit 0
