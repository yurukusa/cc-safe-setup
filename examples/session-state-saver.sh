#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
STATE_DIR="${HOME}/.claude"
COUNTER_FILE="${STATE_DIR}/session-call-count"
STATE_FILE=".claude/session-state.md"
SAVE_INTERVAL=${CC_STATE_SAVE_INTERVAL:-50}
mkdir -p "${STATE_DIR}" 2>/dev/null
mkdir -p "$(dirname "${STATE_FILE}")" 2>/dev/null
COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
if (( COUNT % SAVE_INTERVAL == 0 )); then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    MODIFIED=$(git diff --name-only 2>/dev/null | head -10)
    STAGED=$(git diff --cached --name-only 2>/dev/null | head -10)
    RECENT_COMMITS=$(git log --oneline -5 2>/dev/null)
    cat > "$STATE_FILE" << STATE
Updated: $(date -Iseconds)
${BRANCH}
${MODIFIED:-none}
${STAGED:-none}
${RECENT_COMMITS:-none}
${COUNT}
---
*Read this file after compaction to restore context.*
STATE
    echo "Session state saved (call #${COUNT})" >&2
fi
exit 0
