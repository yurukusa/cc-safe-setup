#!/bin/bash
# dns-config-guard.sh — Block DNS/hosts file modifications
#
# Solves: Claude Code modifying /etc/hosts or /etc/resolv.conf which
#         can redirect traffic, break name resolution, or create
#         security vulnerabilities.
#
# TRIGGER: PreToolUse  MATCHER: "Bash|Edit|Write"

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
