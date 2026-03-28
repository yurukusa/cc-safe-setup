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
