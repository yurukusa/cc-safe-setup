#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE "git\s+rebase" && git log --oneline origin/$(git branch --show-current 2>/dev/null) 2>/dev/null | head -1 | grep -q .; then echo "WARNING: Rebasing pushed branch" >&2; fi
exit 0
