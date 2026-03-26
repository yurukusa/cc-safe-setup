#!/bin/bash
# classifier-fallback-allow.sh — Allow read-only commands when Auto Mode classifier is unavailable
#
# Solves: Auto Mode's safety classifier (Sonnet) sometimes goes down.
#         When it does, ALL commands get blocked — even cat, ls, grep.
#         (#39259, #38618, #38537)
#
# How it works: PermissionRequest hook that approves read-only commands
#               regardless of classifier status. Only fires on PermissionRequest
#               (the permission prompt), not on normal PreToolUse.
#
# Usage: Add to settings.json as a PermissionRequest hook
#
# {
#   "hooks": {
#     "PermissionRequest": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/classifier-fallback-allow.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Extract the base command (first word, ignoring leading whitespace)
BASE=$(echo "$COMMAND" | awk '{print $1}')

# Read-only commands that are always safe
case "$BASE" in
    # File inspection
    cat|head|tail|less|more|wc|file|stat|du|df|ls|tree|find|which|whereis|type|realpath|readlink|basename|dirname)
        # find with -delete is NOT read-only
        if echo "$COMMAND" | grep -qE '\s-delete'; then
            exit 0  # Don't approve — let normal flow handle it
        fi
        jq -n '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow","permissionDecisionReason":"Read-only command (classifier fallback)"}}'
        exit 0
        ;;
    # Text search
    grep|rg|ag|ack)
        jq -n '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow","permissionDecisionReason":"Text search (classifier fallback)"}}'
        exit 0
        ;;
    # Git read-only
    git)
        SUBCMD=$(echo "$COMMAND" | awk '{print $2}')
        case "$SUBCMD" in
            status|log|diff|show|branch|tag|remote|describe|rev-parse|blame|shortlog|ls-files|ls-tree)
                jq -n '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow","permissionDecisionReason":"Git read-only (classifier fallback)"}}'
                exit 0
                ;;
        esac
        ;;
    # Shell builtins
    echo|printf|true|false|pwd|env|printenv|date|uname|hostname|whoami|id)
        jq -n '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow","permissionDecisionReason":"Shell builtin (classifier fallback)"}}'
        exit 0
        ;;
    # JSON/YAML
    jq|yq)
        jq -n '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow","permissionDecisionReason":"Data processing (classifier fallback)"}}'
        exit 0
        ;;
esac

# Not a known read-only command — don't interfere
exit 0
