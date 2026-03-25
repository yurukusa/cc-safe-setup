INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
echo "$TOOL" | grep -q '^mcp__' || exit 0
if [ "${CC_MCP_WARN_ALL:-0}" = "1" ]; then
    echo "NOTE: MCP tool call: $TOOL" >&2
fi
BLOCKED="${CC_MCP_BLOCKED_TOOLS:-}"
if [ -n "$BLOCKED" ]; then
    IFS=',' read -ra PATTERNS <<< "$BLOCKED"
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs)  # trim whitespace
        if [[ "$TOOL" == *"$pattern"* ]]; then
            echo "BLOCKED: MCP tool $TOOL matches blocked pattern: $pattern" >&2
            exit 2
        fi
    done
fi
case "$TOOL" in
    *delete*|*remove*|*drop*|*destroy*|*purge*)
        echo "WARNING: Potentially destructive MCP tool: $TOOL" >&2
        ;;
    *send_email*|*send_message*|*post*|*publish*)
        echo "WARNING: MCP tool with external side effects: $TOOL" >&2
        ;;
esac
exit 0
