#!/bin/bash
# cross-session-error-log.sh — Persist error patterns across sessions
#
# Solves: Agent ignores spec across multiple sessions (#40383).
#         Each new session starts fresh with no memory of previous failures.
#         The same destructive mistakes are repeated session after session.
#
# How it works: PostToolUse hook that logs blocked/failed operations
#   to a persistent file (~/.claude/error-history.log). On SessionStart,
#   checks for recurring patterns and warns the new session about them.
#
# The error history survives session restarts, so the next Claude session
# sees "this operation failed 3 times in previous sessions" before
# attempting it again.
#
# TRIGGER: PostToolUse (log errors) + Notification/SessionStart (read history)
# MATCHER: "" (all tools)

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
EVENT=$(echo "$INPUT" | jq -r '.event // empty' 2>/dev/null)

ERROR_LOG="${HOME}/.claude/error-history.log"
mkdir -p "$(dirname "$ERROR_LOG")"

# On session start: show recent error patterns
if [ "$EVENT" = "session_start" ] || [ "$EVENT" = "SessionStart" ]; then
    if [ -f "$ERROR_LOG" ]; then
        RECENT=$(tail -50 "$ERROR_LOG" | awk -F'|' '{print $3}' | sort | uniq -c | sort -rn | head -5)
        if [ -n "$RECENT" ]; then
            echo "📋 Recurring error patterns from previous sessions:" >&2
            echo "$RECENT" | while read count pattern; do
                [ "$count" -ge 2 ] && echo "  ${count}x: ${pattern}" >&2
            done
        fi
    fi
    exit 0
fi

# On tool use: check for error indicators
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null | head -c 200)
[ -z "$OUTPUT" ] && exit 0

# Detect error patterns
IS_ERROR=false
ERROR_TYPE=""

if echo "$OUTPUT" | grep -qiE "error|failed|BLOCKED|exit code [1-9]|permission denied|not found|syntax error"; then
    IS_ERROR=true
    ERROR_TYPE=$(echo "$OUTPUT" | grep -oiE "error:[^\"]*|failed:[^\"]*|BLOCKED:[^\"]*" | head -1 | head -c 80)
    [ -z "$ERROR_TYPE" ] && ERROR_TYPE="$(echo "$OUTPUT" | head -c 60)"
fi

# Log error with timestamp and tool name
if [ "$IS_ERROR" = "true" ]; then
    TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%S')
    echo "${TIMESTAMP}|${TOOL}|${ERROR_TYPE}" >> "$ERROR_LOG"

    # Keep log manageable (last 200 entries)
    if [ "$(wc -l < "$ERROR_LOG")" -gt 200 ]; then
        tail -100 "$ERROR_LOG" > "${ERROR_LOG}.tmp"
        mv "${ERROR_LOG}.tmp" "$ERROR_LOG"
    fi
fi

exit 0
