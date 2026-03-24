#!/bin/bash
# no-todo-ship.sh — Block commits with TODO/FIXME/HACK markers
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
TODOS=$(git diff --cached 2>/dev/null | grep -cE '^\+.*\b(TODO|FIXME|HACK|XXX)\b' || echo 0)
if [ "$TODOS" -gt 0 ]; then
  echo "WARNING: $TODOS TODO/FIXME/HACK markers in staged changes." >&2
  echo "Resolve them before shipping, or document why they're needed." >&2
fi
exit 0
