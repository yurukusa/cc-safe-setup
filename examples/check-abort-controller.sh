#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "fetch\(" && ! echo "$CONTENT" | grep -qE "AbortController|signal:" && echo "NOTE: fetch() without AbortController/signal — the request cannot be cancelled" >&2
exit 0
