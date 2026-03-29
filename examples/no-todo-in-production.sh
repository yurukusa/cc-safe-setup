#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
COUNT=$(grep -c 'TODO\|FIXME\|HACK\|XXX' "$FILE" 2>/dev/null)
if [[ "$COUNT" -gt 5 ]]; then
    echo "NOTE: $COUNT TODO/FIXME markers in $(basename "$FILE")." >&2
    echo "Consider resolving before shipping." >&2
fi
exit 0
