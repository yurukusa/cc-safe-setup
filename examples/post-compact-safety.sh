#!/bin/bash
# post-compact-safety.sh — Guard against autonomous actions after compaction
#
# Solves: After context compaction, Claude interprets the summary as
# authorization to push commits and make irreversible changes without
# user approval.
# See: https://github.com/anthropics/claude-code/issues/39912
#
# TRIGGER: PreToolUse
# MATCHER: Bash
#
# After compaction, blocks git push and other irreversible commands
# for the first N tool calls, requiring explicit user interaction first.
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/post-compact-safety.sh"
#       }]
#     }]
#   }
# }
#
# Config: CC_POST_COMPACT_GUARD=10 (block for first 10 calls after compact)

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

GUARD_CALLS=${CC_POST_COMPACT_GUARD:-10}
MARKER="/tmp/cc-post-compact-$(whoami)"
COUNTER="/tmp/cc-post-compact-count-$(whoami)"

# Detect compaction (context_window field or session state change)
# After compaction, the session summary often contains these patterns
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Check if we're in post-compact guard mode
if [ -f "$MARKER" ]; then
    COUNT=1
    [ -f "$COUNTER" ] && COUNT=$(( $(cat "$COUNTER") + 1 ))
    echo "$COUNT" > "$COUNTER"

    if [ "$COUNT" -le "$GUARD_CALLS" ]; then
        # Block irreversible commands during guard period
        if echo "$COMMAND" | grep -qE '^\s*(git\s+push|git\s+reset|git\s+clean|npm\s+publish|docker\s+push)'; then
            echo "BLOCKED: Irreversible command blocked (post-compaction safety)" >&2
            echo "  $COUNT/$GUARD_CALLS guard calls remaining. Confirm with user first." >&2
            exit 2
        fi
    else
        # Guard period over
        rm -f "$MARKER" "$COUNTER"
    fi
fi

exit 0
