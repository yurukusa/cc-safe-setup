#!/bin/bash
# clear-command-confirm-guard.sh — Block accidental /clear command
#
# Solves: /clear destroys all conversation context with zero
#         confirmation. Prefix matching means /c + Enter can
#         accidentally trigger /clear instead of /commit or /compact (#40931).
#
# How it works: Blocks /clear entirely. Use /compact to reduce
#   context without losing it.
#
# TRIGGER: UserPromptSubmit
# MATCHER: "^/clear$"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // empty' 2>/dev/null)

if echo "$PROMPT" | grep -qE '^/clear$'; then
  echo "BLOCKED: /clear permanently destroys all context. Use /compact instead to reduce context safely." >&2
  exit 2
fi
exit 0
