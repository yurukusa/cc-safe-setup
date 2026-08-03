#!/bin/bash
# ================================================================
# record-read-coverage.sh — Record how much of each file was read
# ================================================================
# PURPOSE:
#   Two shipped hooks need to know whether a file was read before it
#   is written, and neither could work without this recorder:
#
#     read-before-edit.sh      — documents "Requires companion PostToolUse
#                                hook to record Read events" and no such
#                                hook shipped, so its NOTE fired on every
#                                single Edit (a warning that always fires
#                                carries no information)
#     write-overwrite-confirm.sh — could only compare sizes, so an overwrite
#                                that keeps the line count was invisible
#
# WHY COVERAGE AND NOT JUST THE PATH:
#   Issue #78273: the agent read FIVE lines of a hand-built file, confirmed
#   it had content, then overwrote the whole file with its own analysis.
#   The original was not in git and was unrecoverable. A path-only record
#   would have said "this file was read" and the write would have passed.
#   What matters is whether the part being destroyed was ever seen.
#
# TRIGGER: PostToolUse
# MATCHER: "Read"
#
# RECORD FORMAT (tab separated, appended):
#   <absolute path>\t<offset>\t<limit>\t<total lines when read>
#
#   offset/limit are 0 when the Read carried no such argument, which the
#   Read tool treats as "from the top, up to its own default cap".
# ================================================================

set -uo pipefail

READ_LOG="${CC_READ_LOG:-/tmp/cc-read-files}"

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ "$TOOL" = "Read" ] || exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -n "$FILE" ] || exit 0

# Only real files can be covered. A path that is gone by the time the
# PostToolUse hook runs tells us nothing useful, so record nothing.
[ -f "$FILE" ] || exit 0

OFFSET=$(printf '%s' "$INPUT" | jq -r '.tool_input.offset // 0' 2>/dev/null || echo 0)
LIMIT=$(printf '%s' "$INPUT" | jq -r '.tool_input.limit // 0' 2>/dev/null || echo 0)
case "$OFFSET" in ''|*[!0-9]*) OFFSET=0 ;; esac
case "$LIMIT"  in ''|*[!0-9]*) LIMIT=0  ;; esac

TOTAL=$(wc -l < "$FILE" 2>/dev/null || echo 0)
case "$TOTAL" in ''|*[!0-9]*) TOTAL=0 ;; esac

# The log is advisory state shared between separate hook processes, so a
# failed write must never break the user's Read. Everything here is best effort.
printf '%s\t%s\t%s\t%s\n' "$FILE" "$OFFSET" "$LIMIT" "$TOTAL" >> "$READ_LOG" 2>/dev/null || true

# Keep the log from growing without bound across a long session. 2000 lines is
# far more than any single session needs and costs nothing to carry.
if [ -f "$READ_LOG" ]; then
  LINES=$(wc -l < "$READ_LOG" 2>/dev/null || echo 0)
  case "$LINES" in ''|*[!0-9]*) LINES=0 ;; esac
  if [ "$LINES" -gt 2000 ]; then
    tail -n 1000 "$READ_LOG" > "$READ_LOG.trim" 2>/dev/null &&
      mv "$READ_LOG.trim" "$READ_LOG" 2>/dev/null || true
  fi
fi

exit 0
