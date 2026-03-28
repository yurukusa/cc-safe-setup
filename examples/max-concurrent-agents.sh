#!/bin/bash
# max-concurrent-agents.sh — Limit number of simultaneous subagents
#
# Solves: Uncontrolled agent spawning burns through rate limits and tokens.
#         A single prompt like "research 10 topics" can spawn 10 agents,
#         each consuming context and API calls simultaneously.
#
# How it works: PreToolUse hook on "Agent" that tracks active agents
#   via a counter file. Blocks new agents when the limit is reached.
#   Counter is decremented by a companion PostToolUse hook or timeout.
#
# CONFIG:
#   CC_MAX_AGENTS=3  (default: 3 concurrent agents)
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Agent" ] && exit 0

MAX_AGENTS=${CC_MAX_AGENTS:-3}
COUNTER_FILE="/tmp/cc-agent-count-${PPID}"

# Initialize counter
[ -f "$COUNTER_FILE" ] || echo "0" > "$COUNTER_FILE"

# Read current count
CURRENT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)

# Clean up stale counts (reset if file is older than 10 minutes)
if [ -f "$COUNTER_FILE" ]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$COUNTER_FILE" 2>/dev/null || echo 0) ))
    [ "$AGE" -gt 600 ] && echo "0" > "$COUNTER_FILE" && CURRENT=0
fi

if [ "$CURRENT" -ge "$MAX_AGENTS" ]; then
    echo "BLOCKED: Maximum concurrent agents reached (${CURRENT}/${MAX_AGENTS})" >&2
    echo "  Wait for existing agents to complete before spawning new ones." >&2
    echo "  Set CC_MAX_AGENTS to increase the limit." >&2
    exit 2
fi

# Increment counter
echo $((CURRENT + 1)) > "$COUNTER_FILE"
exit 0
