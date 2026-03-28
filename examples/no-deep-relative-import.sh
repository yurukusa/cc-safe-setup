INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.tsx|*.js|*.jsx) ;; *) exit 0 ;; esac
DEEP=$(grep -nP "from\s+['\"]\.\.\/\.\.\/\.\.\/" "$FILE" 2>/dev/null | head -3)
if [[ -n "$DEEP" ]]; then
    echo "NOTE: Deep relative imports in $(basename "$FILE"):" >&2
    echo "$DEEP" >&2
    echo "Consider: use path aliases (@/ or ~/) for cleaner imports." >&2
fi
exit 0
