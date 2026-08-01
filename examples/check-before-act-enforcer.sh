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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-check-before-act-enforcer-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [check-before-act-enforcer]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
