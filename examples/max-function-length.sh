#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
LINES=$(wc -l < "$FILE" 2>/dev/null)
if [[ "$LINES" -gt 500 ]]; then
    echo "NOTE: $(basename "$FILE") is $LINES lines. Consider splitting." >&2
fi
exit 0
