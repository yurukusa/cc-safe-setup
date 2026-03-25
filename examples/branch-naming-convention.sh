#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bgit\s+(checkout|switch)\s+-b\s+'; then
  BRANCH=$(echo "$COMMAND" | grep -oE '(-b|--create)\s+(\S+)' | awk '{print $2}')
  if [ -n "$BRANCH" ] && ! echo "$BRANCH" | grep -qE '^(feat|fix|chore|docs|test|refactor)/'; then
    echo "WARNING: Branch '$BRANCH' doesn't follow convention." >&2
    echo "Use: feat/, fix/, chore/, docs/, test/, refactor/" >&2
  fi
fi
exit 0
