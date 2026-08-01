#!/bin/bash
# log-truncation-guard.sh — Block log file truncation/deletion
#
# Solves: Claude Code truncating or deleting log files which destroys
#         audit trails and makes debugging incidents impossible.
#
# Detects:
#   > /var/log/syslog        (truncation via redirect)
#   truncate -s 0 <logfile>  (explicit truncation)
#   rm /var/log/*            (log deletion)
#   echo "" > <logfile>      (content erasure)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-log-truncation-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [log-truncation-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block log file truncation
if echo "$COMMAND" | grep -qE '>\s*/var/log/|truncate.*(/var/log/|\.log)|rm\s+.*(/var/log/|\.log)'; then
    echo "BLOCKED: Log file truncation/deletion detected." >&2
    echo "  Destroying logs removes audit trails." >&2
    echo "  Use log rotation instead: logrotate." >&2
    exit 2
fi

exit 0
