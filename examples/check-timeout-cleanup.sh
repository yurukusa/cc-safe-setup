#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "setTimeout\(" && ! echo "$CONTENT" | grep -qE "clearTimeout" && echo "NOTE: setTimeout() without clearTimeout — may fire after teardown/unmount" >&2
exit 0
