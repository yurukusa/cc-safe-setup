COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
STATE="/tmp/cc-subagent-count"; C=$(cat "$STATE" 2>/dev/null || echo 0); echo $((C+1)) > "$STATE"; [ "$C" -gt 5 ] && echo "WARNING: $C subagents spawned this session" >&2
exit 0
