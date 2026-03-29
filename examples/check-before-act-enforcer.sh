#!/bin/bash
# check-before-act-enforcer.sh — Require Read before Edit/Write
#
# Solves: Model ignoring its own rules, editing files without reading (#40289).
#         Claude modifies files it hasn't examined, leading to broken changes
#         because it's working from assumptions instead of actual content.
#
# How it works: PreToolUse hook on Edit/Write that checks a session log
#   for prior Read calls on the same file. If the file hasn't been read
#   in this session, blocks the edit.
#
# Note: cc-safe-setup's built-in read-before-edit.sh also addresses this.
#   This hook adds session-level tracking for stricter enforcement.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only enforce for Edit and Write
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Skip new file creation (Write to non-existent file)
if [ "$TOOL" = "Write" ] && [ ! -f "$FILE" ]; then
  exit 0
fi

# Check session read log
READ_LOG="/tmp/claude-read-log-${PPID:-0}"

if [ -f "$READ_LOG" ] && grep -qF "$FILE" "$READ_LOG" 2>/dev/null; then
  exit 0  # File was read in this session
fi

echo "BLOCKED: You must Read '$FILE' before modifying it." >&2
echo "This ensures you're working with the actual file content," >&2
echo "not assumptions from memory or previous sessions." >&2
exit 2
