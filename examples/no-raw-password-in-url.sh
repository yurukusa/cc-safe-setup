#!/bin/bash
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r ".tool_input.new_string // empty" 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "://\w+:\w+@" && echo "WARNING: Password in URL — use env vars" >&2
exit 0
