#!/bin/bash
# usage-cache-local.sh — Cache usage info locally to avoid API calls
#
# Solves: Asking "how much budget have I used?" costs tokens itself (#39465, 4👍).
#         This hook tracks tool calls locally so you can check usage
#         without making an API call.
#
# How it works: PostToolUse hook. Counts tool calls and estimates cost
#               based on rough token averages. Writes to a local file
#               that can be read with `cat /tmp/cc-usage-<hash>`.
#
# TRIGGER: PostToolUse  MATCHER: ""
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)

STATE="/tmp/cc-usage-$(echo "$PWD" | md5sum | cut -c1-8)"

# Read current state
CALLS=0
READS=0
WRITES=0
BASH_CALLS=0
if [ -f "$STATE" ]; then
    eval "$(cat "$STATE")"
fi

# Increment
CALLS=$((CALLS + 1))
case "$TOOL" in
    Read) READS=$((READS + 1)) ;;
    Edit|Write) WRITES=$((WRITES + 1)) ;;
    Bash) BASH_CALLS=$((BASH_CALLS + 1)) ;;
esac

# Save state
cat > "$STATE" << EOF
CALLS=$CALLS
READS=$READS
WRITES=$WRITES
BASH_CALLS=$BASH_CALLS
STARTED=${STARTED:-$(date +%s)}
EOF

# Show periodic summary (every 50 calls)
if [ $((CALLS % 50)) -eq 0 ]; then
    DURATION=$(( ($(date +%s) - ${STARTED:-$(date +%s)}) / 60 ))
    echo "📊 Session: $CALLS calls ($READS reads, $WRITES writes, $BASH_CALLS bash) in ${DURATION}min" >&2
    echo "   Check anytime: cat $STATE" >&2
fi

exit 0
