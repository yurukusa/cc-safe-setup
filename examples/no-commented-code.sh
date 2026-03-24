CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
COMMENTED=$(echo "$CONTENT" | grep -cE "^\s*(//|#)\s*(if|for|while|function|const|let|var|import|class)" || echo 0); [ "$COMMENTED" -gt 5 ] && echo "NOTE: Large block of commented code — delete or uncomment" >&2
exit 0
