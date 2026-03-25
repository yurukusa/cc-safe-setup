#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "<form.*method.*POST" && ! echo "$CONTENT" | grep -qE "csrf|_token|csrfmiddleware" && echo "NOTE: Form without CSRF protection" >&2
exit 0
