#!/bin/bash
# read-once-guard.sh — Warn when Claude re-reads a file already in context
#
# Inspired by the token waste pattern where Claude reads the same file
# multiple times in a session, consuming tokens without gaining new info.
# Studies show this can waste 30%+ of session tokens.
#
# HOW IT WORKS:
#   Tracks which files have been read in the current session.
#   If a file is read again and hasn't been modified since the last read,
#   warns the user (but allows the read to proceed).
#
# TRIGGER: PreToolUse  MATCHER: "Read"
#
# CONFIGURATION:
#   CC_READ_ONCE_ACTION=warn|block  (default: warn)
#   CC_READ_ONCE_MAX=3              (warn/block after N re-reads of same file)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE_PATH" ]] && exit 0

# Normalize path
FILE_PATH=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

STATE_DIR="/tmp/cc-read-once"
mkdir -p "$STATE_DIR"

ACTION="${CC_READ_ONCE_ACTION:-warn}"
MAX_READS="${CC_READ_ONCE_MAX:-3}"

# Session ID based on parent process
SESSION_ID="${CC_SESSION_ID:-$$}"
STATE_FILE="$STATE_DIR/reads-${SESSION_ID}.log"

# Get current file mtime
CURRENT_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")

# Check if this file was already read
READ_COUNT=0
LAST_MTIME="0"
if [[ -f "$STATE_FILE" ]]; then
  while IFS=$'\t' read -r path mtime count; do
    if [[ "$path" == "$FILE_PATH" ]]; then
      READ_COUNT=$count
      LAST_MTIME=$mtime
      break
    fi
  done < "$STATE_FILE"
fi

# If file was modified since last read, reset counter
if [[ "$CURRENT_MTIME" != "$LAST_MTIME" && "$LAST_MTIME" != "0" ]]; then
  READ_COUNT=0
fi

# Increment read count
READ_COUNT=$((READ_COUNT + 1))

# Update state file (use tab as delimiter to avoid path conflicts)
ESCAPED_PATH=$(printf '%s' "$FILE_PATH" | sed 's/[&/\]/\\&/g')
if grep -q "^${ESCAPED_PATH}	" "$STATE_FILE" 2>/dev/null; then
  # Replace the line for this file
  grep -v "^${ESCAPED_PATH}	" "$STATE_FILE" > "${STATE_FILE}.tmp"
  echo -e "${FILE_PATH}\t${CURRENT_MTIME}\t${READ_COUNT}" >> "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
else
  echo -e "${FILE_PATH}\t${CURRENT_MTIME}\t${READ_COUNT}" >> "$STATE_FILE"
fi

# Check threshold
if [[ "$READ_COUNT" -gt "$MAX_READS" ]]; then
  if [[ "$ACTION" == "block" ]]; then
    echo "⚠️  BLOCKED: ${FILE_PATH} has been read ${READ_COUNT} times without changes." >&2
    echo "   The file content is already in your context. Use what you already know." >&2
    exit 2
  else
    echo "⚠️  NOTE: Re-reading ${FILE_PATH} (${READ_COUNT}x). File hasn't changed since last read." >&2
    echo "   Consider using the content already in your context to save tokens." >&2
  fi
fi

exit 0
