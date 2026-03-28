#!/bin/bash
# api-overload-backoff.sh — Track API overload errors and enforce backoff
#
# Solves: 529 Overloaded errors causing session failures and wasted tokens.
#         Multiple issues: #39743(24👍), #39763(18👍), #39745(14👍),
#         #39767(11👍), #39747(8👍) — 75+ combined reactions.
#         Users lose tokens on retries that hit the same overload.
#
# How it works: PostToolUse hook. Detects 529/overload errors in tool output.
#               Tracks consecutive errors. After 3 consecutive 529s, warns
#               to wait before retrying. After 5, suggests stopping the session.
#
# TRIGGER: PostToolUse  MATCHER: ""
# ================================================================

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null)

[ -z "$OUTPUT" ] && exit 0

STATE="/tmp/cc-overload-count-$$"

# Detect 529/overload patterns in output
if echo "$OUTPUT" | grep -qiE '529|overloaded_error|overload|rate.limit.*exceeded'; then
    # Increment counter
    COUNT=1
    [ -f "$STATE" ] && COUNT=$(( $(cat "$STATE") + 1 ))
    echo "$COUNT" > "$STATE"

    if [ "$COUNT" -ge 5 ]; then
        echo "" >&2
        echo "⚠ API OVERLOAD: $COUNT consecutive 529 errors detected." >&2
        echo "The API is severely overloaded. Continuing will waste tokens." >&2
        echo "Recommendation: Stop this session and retry in 10-15 minutes." >&2
    elif [ "$COUNT" -ge 3 ]; then
        echo "" >&2
        echo "⚠ API OVERLOAD: $COUNT consecutive 529 errors." >&2
        echo "Wait 30-60 seconds before the next action." >&2
    fi
else
    # Reset counter on successful response
    rm -f "$STATE" 2>/dev/null
fi

exit 0
