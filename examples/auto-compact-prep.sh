INPUT=$(cat)
STATE_DIR="${HOME}/.claude"
COUNTER_FILE="${STATE_DIR}/session-call-count"
PREP_FLAG="${STATE_DIR}/compact-prep-done"
CHECKPOINT=".claude/pre-compact-checkpoint.md"
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
if [ "$COUNT" -eq 0 ]; then
    COUNT=1
    echo "$COUNT" > "$COUNTER_FILE"
else
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNTER_FILE"
fi
THRESHOLD=${CC_COMPACT_PREP_THRESHOLD:-200}
if (( COUNT >= THRESHOLD )) && [ ! -f "$PREP_FLAG" ]; then
    mkdir -p "$(dirname "$CHECKPOINT")" 2>/dev/null
    BRANCH=$(git branch --show-current 2>/dev/null || echo "?")
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    LAST_5=$(git log --oneline -5 2>/dev/null)
    cat > "$CHECKPOINT" << CKPT
Saved: $(date -Iseconds) | Tool call: #${COUNT}
Branch: ${BRANCH} | Dirty files: ${DIRTY}
${LAST_5}
Read this file to understand what you were working on before context was compacted.
Check git status and git log for current state. Continue from the last commit.
CKPT
    touch "$PREP_FLAG"
    echo "NOTICE: Context may compact soon (call #${COUNT}). Checkpoint saved to ${CHECKPOINT}" >&2
fi
exit 0
