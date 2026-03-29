#!/bin/bash
# denied-action-retry-guard.sh — Block re-attempts of denied tool calls
#
# Solves: Model retries the same operation after user explicitly denied it (#40156).
#         Claude asks "shall I git push?", user says no, Claude tries git push anyway.
#
# How it works: PreToolUse hook that tracks denied operations via a state file.
#   When a tool call is blocked (exit 2 from any hook), the command signature
#   is recorded. If the same signature appears again, it's auto-blocked.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
COMMAND=""

case "$TOOL" in
  Bash) COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) ;;
  Edit|Write) COMMAND=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) ;;
  *) exit 0 ;;
esac

[ -z "$COMMAND" ] && exit 0

DENY_FILE="/tmp/claude-denied-actions-${PPID:-0}"

# Check if this action was previously denied
if [ -f "$DENY_FILE" ]; then
  # Normalize: take first 80 chars as signature
  SIG=$(echo "$COMMAND" | head -c 80 | md5sum | cut -d' ' -f1)
  if grep -q "$SIG" "$DENY_FILE" 2>/dev/null; then
    echo "BLOCKED: This action was previously denied in this session." >&2
    echo "Do not retry denied actions. Try a different approach." >&2
    exit 2
  fi
fi

exit 0
