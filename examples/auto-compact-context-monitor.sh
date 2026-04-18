#!/bin/bash
# auto-compact-context-monitor.sh — Detect unexpected auto-compaction via context size drops
#
# PreCompact hooks do NOT fire on auto-compaction (only on manual /compact).
# This PostToolUse hook monitors for sudden context size drops that indicate
# auto-compaction occurred without PreCompact firing.
#
# Born from: https://github.com/anthropics/claude-code/issues/50467
# Related: https://github.com/anthropics/claude-code/issues/50492 (24% early fire)
#
# TRIGGER: PostToolUse  MATCHER: ""
# Runs after every tool use to track context size changes.

INPUT=$(cat)

# Track context tokens (approximate via tool input size)
MONITOR_FILE="/tmp/cc-context-monitor-$$"
CURRENT_SIZE=$(echo "$INPUT" | wc -c)

if [ -f "$MONITOR_FILE" ]; then
    PREV_SIZE=$(cat "$MONITOR_FILE")
    # If current input is significantly smaller than previous (>50% drop),
    # auto-compaction likely occurred
    if [ "$PREV_SIZE" -gt 1000 ] && [ "$CURRENT_SIZE" -gt 0 ]; then
        RATIO=$((CURRENT_SIZE * 100 / PREV_SIZE))
        if [ "$RATIO" -lt 30 ]; then
            echo "⚠ AUTO-COMPACTION DETECTED: Context dropped ${RATIO}% (${PREV_SIZE}→${CURRENT_SIZE} bytes)" >&2
            echo "  PreCompact hooks did NOT fire for this compaction (#50467)" >&2
            echo "  Important context may have been lost. Verify key facts." >&2
        fi
    fi
fi

echo "$CURRENT_SIZE" > "$MONITOR_FILE"
exit 0
