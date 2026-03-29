#!/bin/bash
# bg-task-cooldown-guard.sh — Cooldown after background task notifications
#
# Solves: Claude treating background task notifications as user approval (#39038).
#         When a background agent completes, the notification can be mistaken
#         for user consent, leading to unauthorized destructive actions.
#
# How it works: PreToolUse hook on Bash/Edit/Write that checks if a background
#   task completed recently (within CC_BG_COOLDOWN_SECS, default 10).
#   If so, blocks destructive operations until the cooldown expires.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
COOLDOWN="${CC_BG_COOLDOWN_SECS:-10}"
STATE_FILE="/tmp/claude-bg-task-timestamp-${PPID:-0}"

# Check if a background task recently completed
if [ -f "$STATE_FILE" ]; then
  LAST_BG=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  ELAPSED=$((NOW - LAST_BG))

  if [ "$ELAPSED" -lt "$COOLDOWN" ]; then
    # Within cooldown — check if this is a destructive operation
    case "$TOOL" in
      Bash)
        COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        if echo "$COMMAND" | grep -qEi 'rm\s|git\s+(push|reset|clean|checkout\s+--)|drop\s|delete\s|truncate\s'; then
          echo "BLOCKED: Destructive command within ${COOLDOWN}s of background task completion." >&2
          echo "A background task just completed. Wait ${COOLDOWN}s or get explicit user approval." >&2
          exit 2
        fi
        ;;
      Edit|Write)
        # Allow non-destructive edits during cooldown
        ;;
    esac
  fi
fi

exit 0
