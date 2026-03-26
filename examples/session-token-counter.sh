#!/bin/bash
# session-token-counter.sh — Track tool usage count per session
#
# Solves: No visibility into how many tool calls a session makes.
#         Useful for detecting runaway loops and estimating costs.
#         Warns at configurable thresholds (default: 100, 200, 500).
#
# How it works: PostToolUse hook that increments a counter file.
#               At threshold crossings, outputs a warning to stderr.
#               Does NOT block — just tracks and warns.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-token-counter.sh" }]
#     }]
#   }
# }
#
# Environment variables:
#   CC_TOOL_WARN_100  — threshold 1 (default: 100)
#   CC_TOOL_WARN_200  — threshold 2 (default: 200)
#   CC_TOOL_WARN_500  — threshold 3 (default: 500)

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[ -z "$TOOL" ] && exit 0

# Use a session-specific counter file
COUNTER_FILE="${CC_TOOL_COUNTER:-/tmp/cc-session-tool-count-$$}"

# Initialize if not exists
if [ ! -f "$COUNTER_FILE" ]; then
    echo "0" > "$COUNTER_FILE"
fi

# Increment
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Check thresholds
WARN_1=${CC_TOOL_WARN_100:-100}
WARN_2=${CC_TOOL_WARN_200:-200}
WARN_3=${CC_TOOL_WARN_500:-500}

if [ "$COUNT" -eq "$WARN_1" ]; then
    echo "INFO: Session has made $COUNT tool calls. Consider whether you're in a loop." >&2
elif [ "$COUNT" -eq "$WARN_2" ]; then
    echo "WARNING: Session has made $COUNT tool calls. High usage may indicate a runaway loop." >&2
elif [ "$COUNT" -eq "$WARN_3" ]; then
    echo "CRITICAL: Session has made $COUNT tool calls. Very high usage — review session behavior." >&2
fi

exit 0
