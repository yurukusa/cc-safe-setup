INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0
if echo "$CMD" | grep -qE '^\s*docker\s+(build|compose|ps|images|logs|inspect|network\s+ls|volume\s+ls|exec|run)'; then
    echo '{"decision":"approve"}'
    exit 0
fi
if echo "$CMD" | grep -qE '^\s*docker-compose\s+(up|down|build|logs|ps|restart)'; then
    echo '{"decision":"approve"}'
    exit 0
fi
exit 0
