#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
COMMAND=$(echo "$INPUT" | jq -r ".tool_input.command // empty" 2>/dev/null); echo "$COMMAND" | grep -qE "git\s+merge" && echo "NOTE: Check if target branch is ahead before merging." >&2
exit 0
