#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "addEventListener\((['\"])(scroll|resize|mousemove|wheel|drag|input)" && ! echo "$CONTENT" | grep -qE "debounce|throttle" && echo "NOTE: high-frequency event listener without debounce/throttle" >&2
exit 0
