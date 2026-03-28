#!/bin/bash
# network-interface-guard.sh — Block network interface modifications
#
# Solves: Claude Code modifying network interfaces which can cause
#         immediate loss of connectivity on remote servers.
#
# Detects:
#   ifconfig <iface> down    (disable interface)
#   ip link set <iface> down (modern equivalent)
#   ip addr del              (remove IP address)
#   ip route del             (remove route)
#   nmcli connection delete  (NetworkManager)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block interface disable
if echo "$COMMAND" | grep -qE '\bifconfig\s+\S+\s+down\b'; then
    echo "BLOCKED: Disabling network interface will cause connectivity loss." >&2
    exit 2
fi

# Block ip link/addr/route destructive operations
if echo "$COMMAND" | grep -qE '\bip\s+(link\s+set\s+\S+\s+down|addr\s+del|route\s+del)\b'; then
    echo "BLOCKED: Network configuration change can cause connectivity loss." >&2
    exit 2
fi

# Block NetworkManager connection deletion
if echo "$COMMAND" | grep -qE '\bnmcli\s+connection\s+delete\b'; then
    echo "BLOCKED: Deleting NetworkManager connection." >&2
    exit 2
fi

exit 0
