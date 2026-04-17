INPUT=$(cat)
COUNTER_FILE="/tmp/.cc-model-check-counter"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
if [ $((COUNT % 50)) -ne 0 ]; then
    exit 0
fi
SESSION_FILE=$(ls -t ~/.claude/projects/*/session.jsonl 2>/dev/null | head -1)
if [ -n "$SESSION_FILE" ]; then
    MODEL=$(grep -o '"model":"[^"]*"' "$SESSION_FILE" 2>/dev/null | tail -1 | cut -d'"' -f4)
    if echo "$MODEL" | grep -qi "opus-4-7\|opus-4.7"; then
        echo "⚠ Model alert: You're using $MODEL which may consume 3x more tokens than Opus 4.6."
        echo "Consider: claude --model claude-opus-4-6 or add \"model\": \"claude-opus-4-6\" to settings.json"
        echo "See: https://github.com/anthropics/claude-code/issues/49601"
    fi
fi
exit 0
