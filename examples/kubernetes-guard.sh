#!/bin/bash
# kubernetes-guard.sh — Block destructive kubectl commands
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bkubectl\s+delete\s+(namespace|ns|node)\b'; then
    echo "BLOCKED: kubectl delete namespace/node is highly destructive" >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE '\bkubectl\s+delete\s+.*--all\b'; then
    echo "BLOCKED: kubectl delete --all affects all resources in scope" >&2
    exit 2
fi
exit 0
