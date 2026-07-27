#!/bin/bash
# edit-retry-loop-guard.sh — Detect Edit tool stuck retrying the same file
#
# Solves: Edit tool path contamination in long sessions
#         (#35576 — Edit gets "stuck" targeting wrong file, retrying 15+ times)
#
# Tracks consecutive Edit failures on the same file. After 3 failures,
# warns the model to verify the file path.
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[ "$TOOL" = "Edit" ] || exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // empty' 2>/dev/null)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0

STATE_FILE="/tmp/.cc-edit-retry-$(echo "$FILE" | md5sum | cut -c1-8)"

# Check if edit failed (non-zero exit or "no changes" in output)
if [ "$EXIT_CODE" != "0" ] || echo "$OUTPUT" | grep -qiE 'no changes|not found|old_string.*not.*found'; then
    COUNT=1
    [ -f "$STATE_FILE" ] && COUNT=$(( $(cat "$STATE_FILE") + 1 ))
    echo "$COUNT" > "$STATE_FILE"

    if [ "$COUNT" -ge 3 ]; then
        echo "WARNING: Edit has failed $COUNT times on: $FILE" >&2
        echo "  Verify the file path is correct. Use Read to check the current content." >&2
        echo "  The file may have been moved, renamed, or the content changed." >&2
        rm -f "$STATE_FILE"
    fi
else
    # Success — reset counter
    rm -f "$STATE_FILE"
fi

exit 0
