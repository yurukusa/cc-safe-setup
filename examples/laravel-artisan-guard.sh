INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'artisan\s+(db:wipe|migrate:fresh|migrate:reset)'; then
    echo "BLOCKED: Destructive Laravel command." >&2
    echo "Command: $COMMAND" >&2
    echo "db:wipe/migrate:fresh destroy all data." >&2
    echo "Use: artisan migrate (incremental)" >&2
    exit 2
fi
exit 0
