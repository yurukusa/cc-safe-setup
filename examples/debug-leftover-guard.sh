#!/bin/bash
# debug-leftover-guard.sh — Detect debug code in commits
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
LEFTOVERS=$(git diff --cached 2>/dev/null | grep -cE '^\+.*(debugger|console\.debug|pdb\.set_trace|binding\.pry|pp\s|var_dump|print_r)' || echo 0)
if [ "$LEFTOVERS" -gt 0 ]; then
  echo "WARNING: $LEFTOVERS debug statement(s) in staged changes." >&2
  echo "Remove debugger/pdb/binding.pry before committing." >&2
fi
exit 0
