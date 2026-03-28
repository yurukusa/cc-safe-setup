INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qiE 'redis-cli.*FLUSH(ALL|DB)|FLUSHALL|FLUSHDB'; then
    echo "BLOCKED: Redis FLUSHALL/FLUSHDB destroys all data." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi
exit 0
