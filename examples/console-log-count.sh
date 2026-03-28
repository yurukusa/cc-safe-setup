INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.tsx|*.js|*.jsx) ;; *) exit 0 ;; esac
COUNT=$(grep -c 'console\.log' "$FILE" 2>/dev/null)
if [[ "$COUNT" -gt 5 ]]; then
    echo "WARNING: $COUNT console.log statements in $(basename "$FILE")." >&2
    echo "Consider cleaning up debug logs before committing." >&2
fi
exit 0
