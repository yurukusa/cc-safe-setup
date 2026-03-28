#!/bin/bash
# output-explosion-detector.sh — Detect abnormally large tool outputs
#
# Solves: Claude generating massive output without user input (#38029, #38239).
#         A single response with 650K+ output tokens costs $342.
#         This hook tracks cumulative output size and warns at thresholds.
#
# How it works: PostToolUse hook. Measures tool_output length per call.
#               If a single output exceeds threshold, warns immediately.
#               Tracks cumulative session output and warns at milestones.
#
# TRIGGER: PostToolUse  MATCHER: ""
#
# CONFIG:
#   CC_OUTPUT_WARN_SINGLE=50000   (warn if single output > 50KB chars)
#   CC_OUTPUT_WARN_TOTAL=500000   (warn if session total > 500KB chars)
# ================================================================

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[ -z "$OUTPUT" ] && exit 0

OUTPUT_LEN=${#OUTPUT}
SINGLE_THRESHOLD="${CC_OUTPUT_WARN_SINGLE:-50000}"
TOTAL_THRESHOLD="${CC_OUTPUT_WARN_TOTAL:-500000}"

# Check single output size
if [ "$OUTPUT_LEN" -gt "$SINGLE_THRESHOLD" ]; then
    echo "⚠ LARGE OUTPUT: $TOOL produced $(( OUTPUT_LEN / 1000 ))KB in one call." >&2
    echo "This may indicate runaway generation. Consider /compact or stopping." >&2
fi

# Track cumulative output
STATE="/tmp/cc-output-total-$(echo "$PWD" | md5sum | cut -c1-8)"
CURRENT=0
[ -f "$STATE" ] && CURRENT=$(cat "$STATE" 2>/dev/null || echo "0")
CURRENT=$((CURRENT + OUTPUT_LEN))
echo "$CURRENT" > "$STATE"

# Check cumulative thresholds
if [ "$CURRENT" -gt "$TOTAL_THRESHOLD" ]; then
    PREV=$((CURRENT - OUTPUT_LEN))
    if [ "$PREV" -le "$TOTAL_THRESHOLD" ]; then
        echo "⚠ SESSION OUTPUT: $(( CURRENT / 1000 ))KB total output this session." >&2
        echo "High output volume = high token cost. Run /compact to reset." >&2
    fi
fi

exit 0
