#!/bin/bash
# ================================================================
# write-shrink-guard.sh — Block writes that drastically shrink files
# ================================================================
# PURPOSE:
#   Prevents accidental file truncation. When Claude uses the Write
#   tool, if the new content is <10% of the original file size,
#   it's likely a truncation bug, not an intentional edit.
#
#   Real case: 31,699-line file truncated to 16 lines, destroying
#   5 hours of work. (#40807)
#
# TRIGGER: PreToolUse
# MATCHER: "Write"
#
# DECISION: exit 2 = block, exit 0 = allow
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-write-shrink-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [write-shrink-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Write" ] && exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

# Get original file size
OLD_SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
[ "$OLD_SIZE" -lt 1000 ] && exit 0  # Skip small files

# Get new content size
NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
NEW_SIZE=${#NEW_CONTENT}

# Calculate ratio
if [ "$NEW_SIZE" -gt 0 ] && [ "$OLD_SIZE" -gt 0 ]; then
    RATIO=$((NEW_SIZE * 100 / OLD_SIZE))
    if [ "$RATIO" -lt 10 ]; then
        echo "BLOCKED: Write would shrink $(basename "$FILE") from $OLD_SIZE to $NEW_SIZE bytes (${RATIO}% of original)." >&2
        echo "This looks like accidental truncation. Use Edit for targeted changes instead." >&2
        exit 2
    elif [ "$RATIO" -lt 25 ]; then
        echo "WARNING: Write would significantly reduce $(basename "$FILE") from $OLD_SIZE to $NEW_SIZE bytes (${RATIO}%)." >&2
    fi
fi

exit 0
