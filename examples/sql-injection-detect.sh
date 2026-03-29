#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
if echo "$CONTENT" | grep -qE "\".*\+.*\"|'.*\+.*'|f\".*{.*}.*WHERE|query\(.*\+"; then echo "WARNING: Possible SQL injection pattern" >&2; fi
exit 0
