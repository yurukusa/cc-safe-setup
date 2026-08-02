#!/bin/bash
# cron-modification-guard.sh — Block unreviewed cron job modifications
#
# Solves: Claude creating cron jobs that sabotage live services (#40421).
#         A cron job that polls 200 content IDs against a single-connection
#         proxy caused stream resets every 10 minutes for days.
#
# Why this matters:
#   Cron jobs are persistent, invisible, and run unattended. A bad cron
#   can cause sustained damage long after the session ends. This hook
#   blocks crontab edits, /etc/cron.d writes, and systemd timer creation.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-cron-modification-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [cron-modification-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect cron/timer modifications
if echo "$COMMAND" | grep -qEi '(crontab\s+-[elr]|crontab\s+[^-]|systemctl\s+(enable|start|restart)\s+.*\.timer|(^|\s|;|&&|\|)at\s+)'; then
  echo "BLOCKED: Cron/timer modification requires manual review." >&2
  echo "" >&2
  echo "Command: $COMMAND" >&2
  echo "" >&2
  echo "Cron jobs are persistent and run unattended. Before creating one:" >&2
  echo "  1. Will this interfere with live services?" >&2
  echo "  2. Does it access shared resources (DB, API, proxy)?" >&2
  echo "  3. What happens if it fails silently?" >&2
  exit 2
fi

# Also catch writing to cron directories
if echo "$COMMAND" | grep -qE '>\s*/etc/cron\.|tee\s+/etc/cron\.'; then
  echo "BLOCKED: Direct write to cron directory." >&2
  echo "Command: $COMMAND" >&2
  exit 2
fi

exit 0
