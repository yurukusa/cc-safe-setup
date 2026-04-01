INPUT=$(cat)
MSG=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)
if echo "$MSG" | grep -qi "compact"; then
  echo "⚠ Context approaching limit — compaction imminent. Consider /compact or /clear now." >&2
fi
exit 0
