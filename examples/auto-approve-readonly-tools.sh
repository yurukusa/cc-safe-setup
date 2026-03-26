INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
    Read|Glob|Grep)
        jq -n --arg tool "$TOOL" \
            '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","permissionDecision":"allow","permissionDecisionReason":($tool + " is read-only, auto-approved")}}'
        exit 0
        ;;
esac
exit 0
