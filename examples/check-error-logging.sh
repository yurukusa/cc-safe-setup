#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "catch *\(" && ! echo "$CONTENT" | grep -qE "console|log|logger|captureException|report" && echo "NOTE: catch block without any logging" >&2
exit 0
