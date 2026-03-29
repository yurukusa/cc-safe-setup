#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.tsx) ;; *) exit 0 ;; esac
[[ ! -f "$FILE" ]] && exit 0
ANYS=$(grep -nP ':\s*any\b|<any>' "$FILE" 2>/dev/null | grep -v '// eslint-disable\|// @ts-' | head -3)
if [[ -n "$ANYS" ]]; then
    echo "NOTE: Explicit 'any' type in $(basename "$FILE"):" >&2
    echo "$ANYS" >&2
    echo "Consider: use specific types or unknown." >&2
fi
exit 0
