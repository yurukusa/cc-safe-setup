#!/bin/bash
# session-agent-cost-limiter.sh — Cap total subagent spawns per session
#
# Solves: #47049 — User lost £140 overnight when Claude spawned 16+
#   subagents. Each agent gets its own context window = 16x token cost.
#   Existing max-concurrent-agents limits simultaneous agents, but not
#   total spawns over a session. This hook limits the cumulative count.
#
# How it works: Tracks every Agent spawn in a session-scoped counter.
#   After CC_MAX_SESSION_AGENTS total spawns, blocks further agents.
#   Counter resets when the session ends (file keyed by PPID).
#
# CONFIG:
#   CC_MAX_SESSION_AGENTS=10  (default: 10 total agents per session)
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"
# CATEGORY: cost-control

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Agent" ] && exit 0

MAX_TOTAL=${CC_MAX_SESSION_AGENTS:-10}
# Use PPID to track the parent Claude Code process, not this subshell
COUNTER_FILE="/tmp/cc-session-agents-${PPID}"

# Initialize if missing
[ -f "$COUNTER_FILE" ] || echo "0" > "$COUNTER_FILE"

CURRENT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)

if [ "$CURRENT" -ge "$MAX_TOTAL" ]; then
    echo "BLOCKED: Session agent limit reached (${CURRENT}/${MAX_TOTAL} total spawns)." >&2
    echo "  Each subagent opens a new context window and consumes tokens independently." >&2
    echo "  Consider completing existing work before spawning more agents." >&2
    echo "  Override: CC_MAX_SESSION_AGENTS=$((MAX_TOTAL + 5))" >&2
    exit 2
fi

# Increment
echo $((CURRENT + 1)) > "$COUNTER_FILE"
exit 0
