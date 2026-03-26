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
