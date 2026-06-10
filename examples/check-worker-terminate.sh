#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "new Worker\(" && ! echo "$CONTENT" | grep -qE "\.terminate\(" && echo "NOTE: new Worker() without .terminate() — the worker leaks" >&2
exit 0
