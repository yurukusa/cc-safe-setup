#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.js|*.tsx|*.jsx) ;; *) exit 0 ;; esac
if grep -qP 'eval\s*\(`|new Function\s*\(`' "$FILE" 2>/dev/null; then
    echo "WARNING: eval() or new Function() with template literal." >&2
    echo "File: $(basename "$FILE")" >&2
    echo "This is a code injection risk." >&2
fi
exit 0
