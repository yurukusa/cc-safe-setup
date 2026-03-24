#!/bin/bash
# no-git-amend-push.sh — Block amending already-pushed commits
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '\bgit\s+commit\s+--amend' || exit 0
# Check if HEAD is already pushed
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$BRANCH" ]; then
  REMOTE_HEAD=$(git rev-parse "origin/$BRANCH" 2>/dev/null)
  LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null)
  if [ "$REMOTE_HEAD" = "$LOCAL_HEAD" ]; then
    echo "WARNING: Amending a commit that's already pushed to origin/$BRANCH." >&2
    echo "This will require a force-push. Create a new commit instead." >&2
  fi
fi
exit 0
