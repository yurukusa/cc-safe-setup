#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
# PostToolUse matcher: Edit|Write
CONTENT=$(cat | jq -r ".tool_input.new_string // empty" 2>/dev/null); [ -n "$CONTENT" ] && echo "$CONTENT" | grep -q "Access-Control-Allow-Origin.*\*" && echo "WARNING: CORS wildcard (*) detected" >&2
exit 0
