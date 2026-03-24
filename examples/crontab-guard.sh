#!/bin/bash
# crontab-guard.sh — Warn before modifying crontab
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bcrontab\s+(-r|-e|-)'; then
  echo "WARNING: Modifying crontab. Current entries:" >&2
  crontab -l 2>/dev/null | wc -l | xargs -I{} echo "  {} existing cron jobs" >&2
  echo "  Use 'crontab -l' to review before editing." >&2
fi
exit 0
