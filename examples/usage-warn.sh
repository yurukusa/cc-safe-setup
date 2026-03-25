COUNTER="${HOME}/.claude/session-tool-count"
COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER"
WARN1=${CC_USAGE_WARN1:-100}
WARN2=${CC_USAGE_WARN2:-200}
WARN3=${CC_USAGE_WARN3:-300}
case "$COUNT" in
    "$WARN1") echo "NOTE: $COUNT tool calls this session" >&2 ;;
    "$WARN2") echo "WARNING: $COUNT tool calls — consider wrapping up" >&2 ;;
    "$WARN3") echo "ALERT: $COUNT tool calls — approaching typical session limit" >&2 ;;
esac
exit 0
