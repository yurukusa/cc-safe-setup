#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.tsx|*.jsx|*.vue) ;; *) exit 0 ;; esac
INLINE=$(grep -nc 'style={{' "$FILE" 2>/dev/null)
if [[ "$INLINE" -gt 3 ]]; then
    echo "NOTE: $INLINE inline styles in $(basename "$FILE")." >&2
    echo "Consider: use CSS modules, Tailwind, or styled-components." >&2
fi
exit 0
