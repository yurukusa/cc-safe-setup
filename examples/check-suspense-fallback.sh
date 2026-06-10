#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "<Suspense" && ! echo "$CONTENT" | grep -qE "fallback" && echo "NOTE: <Suspense> without a fallback prop" >&2
exit 0
