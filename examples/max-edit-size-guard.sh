#!/bin/bash
# max-edit-size-guard.sh — Warn on very large single edits
# TRIGGER: PreToolUse  MATCHER: "Edit"
# CONFIG: CC_MAX_EDIT_LINES=50
INPUT=$(cat)
OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
[ -z "$OLD" ] && exit 0
MAX="${CC_MAX_EDIT_LINES:-50}"
OLD_LINES=$(echo "$OLD" | wc -l)
NEW_LINES=$(echo "$NEW" | wc -l)
TOTAL=$((OLD_LINES + NEW_LINES))
if [ "$TOTAL" -gt "$MAX" ]; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // "?"' 2>/dev/null)
    echo "WARNING: Large edit ($TOTAL lines) in $FILE." >&2
    echo "Consider breaking into smaller changes for easier review." >&2
fi
exit 0
