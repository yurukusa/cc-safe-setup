INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != *.py ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
STARS=$(grep -n 'from .* import \*' "$FILE" 2>/dev/null | head -3)
if [[ -n "$STARS" ]]; then
    echo "WARNING: Star import in $(basename "$FILE"):" >&2
    echo "$STARS" >&2
    echo "Star imports pollute namespace and hide dependencies." >&2
fi
exit 0
