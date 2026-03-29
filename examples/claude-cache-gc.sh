CLAUDE_DIR="$HOME/.claude"
MAX_AGE_DAYS="${CC_GC_MAX_AGE:-30}"
MAX_SIZE_MB="${CC_GC_MAX_SIZE:-500}"
DRY_RUN="${CC_GC_DRY_RUN:-0}"
find "$CLAUDE_DIR/projects" -name "*.jsonl" -mtime +"$MAX_AGE_DAYS" -type f 2>/dev/null | while read f; do
    [ "$DRY_RUN" = "1" ] && echo "  [dry-run] would delete: $f" >&2 && continue
    rm "$f"
done
find "$CLAUDE_DIR/projects" -maxdepth 1 -type d -empty -delete 2>/dev/null
find "$CLAUDE_DIR" -path "*/tool-results/*" -mtime +"$MAX_AGE_DAYS" -type f -delete 2>/dev/null
TOTAL_MB=$(du -sm "$CLAUDE_DIR" 2>/dev/null | cut -f1)
if [ "$TOTAL_MB" -gt "$MAX_SIZE_MB" ] 2>/dev/null; then
    echo "~/.claude is ${TOTAL_MB}MB (cap: ${MAX_SIZE_MB}MB)" >&2
fi
exit 0
