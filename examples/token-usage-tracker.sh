INPUT=$(cat)
# 記録の場所を推測しない。フックに渡される transcript_path を使う。
# 以前は ~/.claude/projects/*/sessions/*/transcript.jsonl を見ていたが、
# その場所は実在せず、glob が空 → [ -f "" ] が偽 → exit 0 で、
# このフックは起動して何もせずに終わっていた（記録も警告も一度も出ない）。
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -f "$TRANSCRIPT" ] || TRANSCRIPT=$(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -1)
[ -f "$TRANSCRIPT" ] || exit 0
USAGE=$(tail -20 "$TRANSCRIPT" | grep -o '"usage":{[^}]*}' | tail -1)
if [ -n "$USAGE" ]; then
    IN=$(echo "$USAGE" | grep -o '"input_tokens":[0-9]*' | grep -o '[0-9]*')
    OUT=$(echo "$USAGE" | grep -o '"output_tokens":[0-9]*' | grep -o '[0-9]*')
    TOTAL=$((${IN:-0} + ${OUT:-0}))
    echo "$(date -Iseconds) in=${IN:-0} out=${OUT:-0} total=$TOTAL" >> ~/.claude/token-usage.log
    BUDGET="${CC_TOKEN_BUDGET:-500000}"
    SUM=$(awk -F'total=' '{sum+=$2}END{print sum+0}' ~/.claude/token-usage.log 2>/dev/null)
    [ "${SUM:-0}" -gt "$BUDGET" ] && echo "Token usage: ~$SUM (budget: $BUDGET)" >&2
fi
exit 0
