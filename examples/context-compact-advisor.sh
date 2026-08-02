INPUT=$(cat)
COUNTER="/tmp/cc-tool-count-$$"
COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER"
THRESHOLD="${CC_COMPACT_THRESHOLD:-50}"
if [ "$((COUNT % THRESHOLD))" -eq 0 ]; then
    # 記録の場所を推測しない（旧: projects/*/sessions/*/transcript.jsonl は実在せず、
    # glob が空のまま黙って何も助言しなかった）。
    TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    [ -f "$TRANSCRIPT" ] || TRANSCRIPT=$(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -1)
    if [ -f "$TRANSCRIPT" ]; then
        SIZE_KB=$(($(wc -c < "$TRANSCRIPT") / 1024))
        if [ "$SIZE_KB" -gt 200 ]; then
            echo "Context ~${SIZE_KB}KB ($COUNT calls). Consider /compact." >&2
        fi
    fi
fi
exit 0
