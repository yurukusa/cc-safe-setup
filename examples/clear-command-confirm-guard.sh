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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-clear-command-confirm-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [clear-command-confirm-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)

if echo "$PROMPT" | grep -qE '^/clear$'; then
  echo "BLOCKED: /clear permanently destroys all context. Use /compact instead to reduce context safely." >&2
  exit 2
fi
exit 0
