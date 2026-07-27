#!/bin/bash
# ================================================================
# read-loop-detector.sh — Surface same-file Read loops within a session
# ================================================================
# PURPOSE:
#   When Claude Code decides to write a memory file (or any output)
#   it sometimes re-reads source files it already read earlier in the
#   same session, looping 10+ times before finally writing. The
#   "File unchanged since last read" cache hint logs through the
#   harness but does not short-circuit the model's decision, so the
#   loop bills tokens for round-trips that return identical content.
#
#   This hook surfaces the loop while it's happening so the user can
#   interrupt with `escape` and prompt the model to write directly.
#
#   Reference: https://github.com/anthropics/claude-code/issues/53578
#              https://github.com/anthropics/claude-code/issues/40123
#
# TRIGGER: PostToolUse  MATCHER: "Read"
#
# CONFIG:
#   CC_READ_LOOP_THRESHOLD=3              (warn at this many reads of same path)
#   CC_READ_LOOP_LOG_DIR=/tmp             (per-session counter log location)
#   CC_READ_LOOP_DISABLE=                 (set to 1 to disable)
# ================================================================

[ "${CC_READ_LOOP_DISABLE:-}" = "1" ] && exit 0

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ "$TOOL_NAME" != "Read" ] && exit 0
[ -z "$FILE_PATH" ] && exit 0

THRESHOLD="${CC_READ_LOOP_THRESHOLD:-3}"
LOG_DIR="${CC_READ_LOOP_LOG_DIR:-/tmp}"
LOG_FILE="$LOG_DIR/cc-read-loop-${SESSION_ID}.log"

# Defensive: ensure threshold is a positive integer
case "$THRESHOLD" in
    ''|*[!0-9]*) THRESHOLD=3 ;;
esac

# Append this read; one path per line for grep -c
printf '%s\n' "$FILE_PATH" >> "$LOG_FILE" 2>/dev/null || exit 0

# Count occurrences of this exact path (literal string, not regex)
COUNT=$(grep -cFx "$FILE_PATH" "$LOG_FILE" 2>/dev/null || echo 0)

if [ "$COUNT" -ge "$THRESHOLD" ]; then
    echo "NOTE: Read on $FILE_PATH has fired $COUNT times this session." >&2
    echo "If the agent is preparing to write a memory or summary file, the model may be re-verifying context it already has." >&2
    echo "To break the loop: escape and prompt 'Stop reading. Write the file now using existing context.'" >&2
    echo "Disable this hint: export CC_READ_LOOP_DISABLE=1" >&2
fi

exit 0
