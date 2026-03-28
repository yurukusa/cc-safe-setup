INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.tsx|*.js|*.jsx) ;; *) exit 0 ;; esac
FLOATS=$(grep -nP '^\s+\w+\.\w+\(' "$FILE" 2>/dev/null | grep -P '\.(then|catch|finally)\(' | grep -v 'await\|return\|const\|let\|var' | head -3)
if [[ -n "$FLOATS" ]]; then
    echo "NOTE: Possible floating promise in $(basename "$FILE"):" >&2
    echo "$FLOATS" >&2
fi
exit 0
