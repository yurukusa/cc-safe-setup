#!/bin/bash
# prompt-length-guard.sh — UserPromptSubmit hook
# Trigger: UserPromptSubmit
# Matcher: ""
#
# Warns when a user prompt exceeds a character threshold.
# Very long prompts can consume excessive context and tokens.
# Adjust THRESHOLD to match your comfort level.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

THRESHOLD=5000
LENGTH=${#PROMPT}

if [ "$LENGTH" -gt "$THRESHOLD" ]; then
  echo "⚠ Long prompt detected: ${LENGTH} chars (threshold: ${THRESHOLD})" >&2
  echo "  Consider breaking this into smaller, focused instructions." >&2
fi

exit 0
