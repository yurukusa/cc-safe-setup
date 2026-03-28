#!/bin/bash
# firewall-guard.sh — Block firewall rule modifications
#
# Solves: Claude Code modifying firewall rules (iptables, ufw, nftables)
#         which can lock users out of servers or expose services.
#         A single wrong iptables rule can make a remote server
#         permanently inaccessible.
#
# Detects:
#   iptables -A/-D/-I/-F    (add/delete/insert/flush rules)
#   ufw allow/deny/delete   (uncomplicated firewall changes)
#   nft add/delete/flush    (nftables changes)
#   firewall-cmd --add/--remove  (firewalld changes)
#
# Does NOT block:
#   iptables -L/-S          (listing rules — read-only)
#   ufw status              (checking status)
#   nft list                (listing rules)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block iptables modifications
if echo "$COMMAND" | grep -qE '\biptables\s+(-A|-D|-I|-F|-X|-P|--append|--delete|--insert|--flush)'; then
    echo "BLOCKED: iptables modification can lock you out of the server." >&2
    echo "  Use 'iptables -L' to view rules safely." >&2
    exit 2
fi

# Block ufw modifications
if echo "$COMMAND" | grep -qE '\bufw\s+(allow|deny|delete|disable|reset|route)'; then
    echo "BLOCKED: ufw firewall modification." >&2
    echo "  Use 'ufw status' to view rules safely." >&2
    exit 2
fi

# Block nftables modifications
if echo "$COMMAND" | grep -qE '\bnft\s+(add|delete|flush|insert)'; then
    echo "BLOCKED: nftables modification." >&2
    exit 2
fi

# Block firewalld modifications
if echo "$COMMAND" | grep -qE '\bfirewall-cmd\s+--(add|remove|set|reload)'; then
    echo "BLOCKED: firewalld modification." >&2
    exit 2
fi

exit 0
