#!/bin/bash
# systemd-service-guard.sh — Block dangerous systemd service operations
#
# Solves: Claude Code stopping/restarting system services without
#         understanding the impact. Stopping nginx kills all connections,
#         stopping postgresql causes data loss if not cleanly shut down.
#
# Detects:
#   systemctl stop <service>
#   systemctl restart <service>
#   systemctl disable <service>
#   systemctl mask <service>
#   service <name> stop
#
# Does NOT block:
#   systemctl status <service>
#   systemctl start <service>    (starting is generally safe)
#   systemctl list-units
#   journalctl
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block systemctl stop/restart/disable/mask
if echo "$COMMAND" | grep -qE '\bsystemctl\s+(stop|restart|disable|mask)\b'; then
    ACTION=$(echo "$COMMAND" | grep -oE 'systemctl\s+(stop|restart|disable|mask)\s+\S+')
    echo "BLOCKED: Dangerous systemd operation: $ACTION" >&2
    echo "  Stopping/restarting services can cause downtime and data loss." >&2
    echo "  Use 'systemctl status <service>' to check before acting." >&2
    exit 2
fi

# Block legacy service command
if echo "$COMMAND" | grep -qE '\bservice\s+\S+\s+(stop|restart)\b'; then
    echo "BLOCKED: Dangerous service operation." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

exit 0
