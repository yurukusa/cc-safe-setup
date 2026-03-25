#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "req\.(body|query|params)\.\w+" && ! echo "$CONTENT" | grep -qE "validate|sanitize|Joi|zod|yup" && echo "NOTE: User input without validation" >&2
exit 0
