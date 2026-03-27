#!/bin/bash
# session-drift-guard.sh — Progressive safety as session ages
#
# Solves: After ~6 hours, Claude starts ignoring CLAUDE.md rules,
# acting autonomously, creating duplicates, corrupting files.
# See: https://github.com/anthropics/claude-code/issues/32963
#
# TRIGGER: PreToolUse
# MATCHER: Bash,Edit,Write
#
# As tool call count grows, the hook progressively tightens:
#   0-200:   Normal (no action)
#   200-500: Warn every 50 calls about drift risk
#   500+:    Block destructive commands (rm, git push, git reset)
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash,Edit,Write",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/session-drift-guard.sh"
#       }]
#     }]
#   }
# }
#
# Config: CC_DRIFT_WARN=200  CC_DRIFT_BLOCK=500

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

WARN_THRESHOLD=${CC_DRIFT_WARN:-200}
BLOCK_THRESHOLD=${CC_DRIFT_BLOCK:-500}
COUNTER="/tmp/cc-drift-counter-$(whoami)"

# Increment counter
COUNT=1
if [ -f "$COUNTER" ]; then
    COUNT=$(( $(cat "$COUNTER") + 1 ))
fi
echo "$COUNT" > "$COUNTER"

# Phase 1: Normal (no action)
if [ "$COUNT" -lt "$WARN_THRESHOLD" ]; then
    exit 0
fi

# Phase 2: Warn periodically
if [ "$COUNT" -lt "$BLOCK_THRESHOLD" ]; then
    if [ $(( COUNT % 50 )) -eq 0 ]; then
        echo "⚠ Session drift warning: $COUNT tool calls" >&2
        echo "  Long sessions degrade AI judgment. Consider /compact or restarting." >&2
    fi
    exit 0
fi

# Phase 3: Block destructive commands
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?(rm|git\s+push|git\s+reset|git\s+clean|git\s+checkout\s+--)\b'; then
    echo "BLOCKED: Destructive command after $COUNT tool calls (drift risk)" >&2
    echo "Session has exceeded $BLOCK_THRESHOLD tool calls." >&2
    echo "Restart the session or use /compact before destructive operations." >&2
    exit 2
fi

# Non-destructive commands still pass with warning
if [ $(( COUNT % 100 )) -eq 0 ]; then
    echo "⚠ High drift risk: $COUNT tool calls. Consider restarting." >&2
fi

exit 0
