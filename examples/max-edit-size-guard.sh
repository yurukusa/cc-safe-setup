#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-max-edit-size-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [max-edit-size-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Edit" ] && exit 0
MAX_LINES=${CC_MAX_EDIT_LINES:-200}
OLD_LINES=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null | wc -l)
NEW_LINES=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | wc -l)
if [ "$OLD_LINES" -gt "$MAX_LINES" ] || [ "$NEW_LINES" -gt "$MAX_LINES" ]; then
    echo "BLOCKED: Edit too large (old: ${OLD_LINES} lines, new: ${NEW_LINES} lines, max: ${MAX_LINES})" >&2
    echo "Break the edit into smaller chunks or use Write to replace the entire file." >&2
    exit 2
fi
exit 0
