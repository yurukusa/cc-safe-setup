INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL" != "Agent" ]] && exit 0
MAX_AGENTS=${CC_MAX_SUBAGENTS:-5}
TRACKER="${HOME}/.claude/active-agents"
mkdir -p "$(dirname "$TRACKER")" 2>/dev/null
NOW=$(date +%s)
ACTIVE=0
if [ -f "$TRACKER" ]; then
    while IFS= read -r line; do
        TS=$(echo "$line" | cut -d'|' -f1)
        AGE=$(( NOW - TS ))
        if (( AGE < 1800 )); then
            ACTIVE=$((ACTIVE + 1))
        fi
    done < "$TRACKER"
fi
if (( ACTIVE >= MAX_AGENTS )); then
    echo "BLOCKED: $ACTIVE active subagents (max: $MAX_AGENTS)." >&2
    echo "Wait for existing agents to complete before spawning more." >&2
    echo "Override: CC_MAX_SUBAGENTS=10" >&2
    exit 2
fi
echo "${NOW}|agent" >> "$TRACKER"
if [ -f "$TRACKER" ]; then
    TMP=$(mktemp)
    while IFS= read -r line; do
        TS=$(echo "$line" | cut -d'|' -f1)
        AGE=$(( NOW - TS ))
        (( AGE < 1800 )) && echo "$line"
    done < "$TRACKER" > "$TMP"
    mv "$TMP" "$TRACKER"
fi
exit 0
