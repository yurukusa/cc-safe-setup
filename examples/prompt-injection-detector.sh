#!/bin/bash
# prompt-injection-detector.sh — UserPromptSubmit hook
# Trigger: UserPromptSubmit
# Matcher: ""
#
# Detects common prompt injection patterns in user prompts.
# Useful in environments where prompts may come from external sources
# (API, shared sessions, automated pipelines).
#
# See: https://github.com/anthropics/claude-code/issues/34895
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Check for common injection patterns
if echo "$PROMPT" | grep -qiE 'ignore (all |previous |prior |above )?(instructions|rules|guidelines)|disregard (your|the) (instructions|rules)|you are now|new persona|system prompt|</?system>|forget (your|everything|all)'; then
  echo "⚠ Possible prompt injection detected in input." >&2
  echo "  Pattern matched: override/ignore instructions" >&2
  echo "  Review the prompt carefully before proceeding." >&2
fi

exit 0
