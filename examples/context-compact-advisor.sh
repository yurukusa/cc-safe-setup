INPUT=$(cat)
COUNTER="/tmp/cc-tool-count-$$"
COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER"
THRESHOLD="${CC_COMPACT_THRESHOLD:-50}"
if [ "$((COUNT % THRESHOLD))" -eq 0 ]; then
    TRANSCRIPT=$(ls -t ~/.claude/projects/*/sessions/*/transcript.jsonl 2>/dev/null | head -1)
    if [ -f "$TRANSCRIPT" ]; then
        SIZE_KB=$(($(wc -c < "$TRANSCRIPT") / 1024))
        if [ "$SIZE_KB" -gt 200 ]; then
            echo "Context ~${SIZE_KB}KB ($COUNT calls). Consider /compact." >&2
        fi
    fi
fi
exit 0
