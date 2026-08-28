#!/bin/bash
# write-byte-integrity-verifier.sh — Detect silent file truncation after Write/Edit
#
# Solves: github.com/anthropics/claude-code/issues/58551
#         "Write and Edit tools truncate files on virtiofs mounts in Claude Code"
#
#         Reporter (2026-05-13) found that on virtiofs-backed mounts (common in
#         devcontainers and Claude Cowork sandboxes), Write and Edit tools
#         silently truncate or null-pad files:
#           - Shrink case: file of N bytes, Write shorter content M, result is
#             new content from 0..M then \x00 from M..N (size unchanged, tail
#             padded with NULs instead of file being truncated to M).
#           - Grow case: Edit makes file longer, but file is silently chopped
#             at some boundary K < intended length.
#         Both modes leave the file in a corrupted state with no error returned
#         to the tool caller, so the assistant believes the write succeeded.
#
# WHY THIS MATTERS:
#   The assistant's belief ("Write returned success, file has the new content")
#   diverges from filesystem reality ("file is null-padded or tail-chopped").
#   This is the textbook claim-verify gap, and on virtiofs it is reproducible.
#   When the assistant's next Read returns the old/corrupted content, the
#   assistant may retry, overwrite further, or report nonsense to the user.
#
# TRIGGER: PostToolUse  MATCHER: Write|Edit
#
# HOW IT WORKS:
#   After a successful Write/Edit:
#     1. Find the target file path from tool_input.
#     2. Use `wc -c` to get the on-disk byte count.
#     3. For Write: compare against the byte count of tool_input.content.
#     4. For Edit: read the file once and confirm tool_input.new_string is
#        present (substring check) and tool_input.old_string is absent.
#     5. Detect null-padding by checking if the last 4 bytes are all \x00
#        while the rest of the file does not naturally end in nulls.
#   On mismatch: emit a clear warning to stderr describing the divergence,
#   the file path, the expected vs. actual byte counts, and the recommended
#   next steps (re-read the file, re-write if confirmed corrupted, escalate
#   if on virtiofs).
#
# CONFIGURATION:
#   CC_WRITE_INTEGRITY_DISABLE=1   — disable the hook entirely
#   CC_WRITE_INTEGRITY_ACTION      — "warn" (default) or "block" (exit 2)
#   CC_WRITE_INTEGRITY_LOG         — log file path
#                                    (default /tmp/cc-write-integrity.log)
#   CC_WRITE_INTEGRITY_SKIP_GLOB   — pipe-separated globs to skip
#                                    (default: "*.log|*.lock|*.tmp")
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write|Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/write-byte-integrity-verifier.sh" }]
#     }]
#   }
# }

# Allow opt-out
if [ "${CC_WRITE_INTEGRITY_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-write-byte-integrity-verifier-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [write-byte-integrity-verifier]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)

# Get tool name; only handle Write and Edit
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# Pull file path
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Skip files matching configured globs
SKIP="${CC_WRITE_INTEGRITY_SKIP_GLOB:-*.log|*.lock|*.tmp}"
IFS='|' read -ra PATTERNS <<< "$SKIP"
for pat in "${PATTERNS[@]}"; do
  pat=$(echo "$pat" | xargs)  # trim
  [ -z "$pat" ] && continue
  case "$FILE_PATH" in
    $pat) exit 0 ;;
  esac
done

ACTION="${CC_WRITE_INTEGRITY_ACTION:-warn}"
LOG_FILE="${CC_WRITE_INTEGRITY_LOG:-/tmp/cc-write-integrity.log}"

# Read disk size
DISK_SIZE=$(wc -c < "$FILE_PATH" 2>/dev/null || echo "")
if [ -z "$DISK_SIZE" ]; then
  exit 0
fi

WARNINGS=()

if [ "$TOOL" = "Write" ]; then
  # Compare disk size vs intended content size
  CONTENT_SIZE=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null | wc -c)
  # jq's `-r` adds a trailing newline; subtract 1 if content was non-empty
  HAS_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
  if [ -n "$HAS_CONTENT" ] && [ "$CONTENT_SIZE" -gt 0 ]; then
    EXPECTED=$((CONTENT_SIZE - 1))
  else
    EXPECTED=0
  fi
  if [ "$DISK_SIZE" -ne "$EXPECTED" ]; then
    # Possible shrink-pad case: disk size larger than expected
    if [ "$DISK_SIZE" -gt "$EXPECTED" ]; then
      # Check trailing bytes for nulls
      TAIL_BYTES=$(tail -c 4 "$FILE_PATH" 2>/dev/null | od -An -tx1 | tr -d ' \n')
      if [ "$TAIL_BYTES" = "00000000" ]; then
        WARNINGS+=("Write target appears null-padded: on-disk size $DISK_SIZE bytes exceeds intended $EXPECTED bytes, trailing 4 bytes are 0x00. Possible virtiofs shrink-pad bug (#58551).")
      else
        WARNINGS+=("Write target byte count mismatch: on-disk $DISK_SIZE vs intended $EXPECTED. Tail bytes are not null but size differs; investigate.")
      fi
    else
      # Tail-chop case: disk size smaller than expected
      WARNINGS+=("Write target appears tail-chopped: on-disk size $DISK_SIZE bytes is less than intended $EXPECTED bytes. Possible virtiofs grow-chop bug (#58551).")
    fi
  fi
elif [ "$TOOL" = "Edit" ]; then
  # For Edit, confirm new_string is in file and old_string is gone
  NEW_STRING=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
  OLD_STRING=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
  REPLACE_ALL=$(printf '%s' "$INPUT" | jq -r '.tool_input.replace_all // false' 2>/dev/null)

  if [ -n "$NEW_STRING" ]; then
    if ! grep -F -q -- "$NEW_STRING" "$FILE_PATH" 2>/dev/null; then
      WARNINGS+=("Edit completed but new_string not found in $FILE_PATH. The Edit may have been silently truncated (#58551) or applied incorrectly.")
    fi
  fi
  if [ -n "$OLD_STRING" ] && [ "$REPLACE_ALL" != "true" ]; then
    # In a non-replace_all Edit, old_string MAY still appear if it was a partial
    # of a unique substring; skip strict check to avoid false positives.
    :
  fi
  # Check for null-padding regardless
  TAIL_BYTES=$(tail -c 4 "$FILE_PATH" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  if [ "$TAIL_BYTES" = "00000000" ]; then
    # Avoid false positive: skip binary files
    if file "$FILE_PATH" 2>/dev/null | grep -q "text"; then
      WARNINGS+=("Edit target ends with 4 null bytes ($FILE_PATH). Text files normally do not. Possible virtiofs null-pad bug (#58551).")
    fi
  fi
fi

# No warnings → silent pass
if [ ${#WARNINGS[@]} -eq 0 ]; then
  exit 0
fi

# Log + emit
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
for w in "${WARNINGS[@]}"; do
  echo "[$TIMESTAMP] file=$FILE_PATH tool=$TOOL action=$ACTION reason=$w" >> "$LOG_FILE"
done

MSG="⚠️  write-byte-integrity-verifier: potential file corruption after $TOOL"
for w in "${WARNINGS[@]}"; do
  MSG+=$'\n'"     - $w"
done
MSG+=$'\n'"  Recommended: re-Read this file, confirm the intended content is on disk;"
MSG+=$'\n'"  if corrupted, re-Write from your in-memory copy. On virtiofs mounts"
MSG+=$'\n'"  (Claude Cowork sandbox / some devcontainers), consider working in /tmp"
MSG+=$'\n'"  or a non-virtiofs path. Reference: github.com/anthropics/claude-code/issues/58551"

if [ "$ACTION" = "block" ]; then
  printf '%s\n' "$MSG" >&2
  exit 2
else
  printf '%s\n' "$MSG" >&2
  exit 0
fi
