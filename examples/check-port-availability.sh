#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
COMMAND=$(cat | jq -r ".tool_input.command // empty" 2>/dev/null); echo "$COMMAND" | grep -qE "listen\(|--port|:3000|:8080" && echo "NOTE: Check port availability before starting server" >&2
exit 0
