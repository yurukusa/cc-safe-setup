#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-subagent-budget-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [subagent-budget-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
