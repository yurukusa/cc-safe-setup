#!/bin/bash
# dns-config-guard.sh — Block DNS/hosts file modifications
#
# Solves: Claude Code modifying /etc/hosts or /etc/resolv.conf which
#         can redirect traffic, break name resolution, or create
#         security vulnerabilities.
#
# TRIGGER: PreToolUse  MATCHER: "Bash|Edit|Write"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-dns-config-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [dns-config-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

case "$TOOL" in
    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        [ -z "$CMD" ] && exit 0
        if echo "$CMD" | grep -qE '(echo|tee|sed|awk).*(/etc/hosts|/etc/resolv\.conf|/etc/nsswitch)'; then
            echo "BLOCKED: DNS configuration modification detected." >&2
            exit 2
        fi
        ;;
    Edit|Write)
        FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        if echo "$FILE" | grep -qE '/etc/hosts$|/etc/resolv\.conf$|/etc/nsswitch\.conf$'; then
            echo "BLOCKED: Cannot modify DNS configuration file: $FILE" >&2
            exit 2
        fi
        ;;
esac

exit 0
