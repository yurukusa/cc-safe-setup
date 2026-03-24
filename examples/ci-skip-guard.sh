#!/bin/bash
# ci-skip-guard.sh — Warn when commit message skips CI
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
if echo "$COMMAND" | grep -qiE '\[skip ci\]|\[ci skip\]|\[no ci\]|--no-verify'; then
  echo "WARNING: Commit will skip CI checks." >&2
  echo "Remove [skip ci] or --no-verify unless you have a good reason." >&2
fi
exit 0
