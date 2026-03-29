#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE "git\s+(commit|push|merge).*--no-verify"; then echo "WARNING: --no-verify bypasses git hooks" >&2; fi
exit 0
