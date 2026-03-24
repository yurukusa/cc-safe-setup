#!/bin/bash
# ================================================================
# permission-cache.sh — Remember approved commands in session
# ================================================================
# PURPOSE:
#   Claude asks permission for the same safe command repeatedly.
#   This hook caches approved command patterns within a session,
#   auto-approving on subsequent calls. Resets when the state
#   file is deleted (new session).
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Only caches commands that match safe patterns (not destructive).
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Never cache destructive commands
echo "$COMMAND" | grep -qE '(rm\s+-rf|git\s+reset|git\s+clean|git\s+push.*--force|sudo|chmod\s+777)' && exit 0

STATE="/tmp/cc-permission-cache-$(echo "$PWD" | md5sum | cut -c1-8)"

# Normalize command (strip args that change, keep base command)
BASE=$(echo "$COMMAND" | awk '{print $1, $2}' | head -c 40)
HASH=$(echo "$BASE" | md5sum | cut -c1-12)

if grep -q "^$HASH$" "$STATE" 2>/dev/null; then
    # Already approved in this session
    echo "{\"decision\":\"approve\",\"reason\":\"Previously approved in this session\"}"
    exit 0
fi

# Record for future calls (will be approved by the normal flow)
echo "$HASH" >> "$STATE" 2>/dev/null

exit 0
