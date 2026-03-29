#!/bin/bash
# subagent-tool-call-limiter.sh — Limit total tool calls per session
#
# Solves: Subagents making unbounded tool calls (#36727).
#         One user reported 234 tool calls in 1.5 hours from a single subagent.
#         Existing rate limiters check frequency, not total count.
#
# How it works: PreToolUse hook (all tools) that increments a counter file.
#   When CC_MAX_TOOL_CALLS (default 200) is reached, blocks further calls.
#
# TRIGGER: PreToolUse
# MATCHER: ""

set -euo pipefail

MAX_CALLS="${CC_MAX_TOOL_CALLS:-200}"
COUNTER_FILE="/tmp/claude-tool-call-counter-$$"

# Use session-based counter (PID of parent process)
PPID_FILE="/tmp/claude-tool-call-counter-${PPID:-0}"
[ -f "$PPID_FILE" ] && COUNTER_FILE="$PPID_FILE"

# Initialize or read counter
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
else
  COUNT=0
  COUNTER_FILE="$PPID_FILE"
fi

COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Check limit
if [ "$COUNT" -gt "$MAX_CALLS" ]; then
  echo "BLOCKED: Tool call limit reached ($COUNT/$MAX_CALLS)." >&2
  echo "This session has made $COUNT tool calls (limit: $MAX_CALLS)." >&2
  echo "Consider starting a new session or increasing CC_MAX_TOOL_CALLS." >&2
  exit 2
fi

# Warn at 80%
WARN_AT=$((MAX_CALLS * 80 / 100))
if [ "$COUNT" -eq "$WARN_AT" ]; then
  echo "WARNING: $COUNT/$MAX_CALLS tool calls used (80%). Consider wrapping up." >&2
fi

exit 0
