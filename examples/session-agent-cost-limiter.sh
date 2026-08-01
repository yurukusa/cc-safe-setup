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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-session-agent-cost-limiter-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [session-agent-cost-limiter]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
