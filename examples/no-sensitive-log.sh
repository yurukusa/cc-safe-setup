COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qiE "console\.\(log\|warn\|error\).*password|log.*token|print.*secret"; then echo "WARNING: Logging sensitive data" >&2; fi
exit 0
