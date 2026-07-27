#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "TODO[^(]|FIXME[^(]" && ! echo "$CONTENT" | grep -qE "TODO\(#|FIXME\(#" && echo "NOTE: TODO without issue reference" >&2
exit 0
