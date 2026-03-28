INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != *.vue ]] && exit 0
if command -v npx &>/dev/null && [[ -f "package.json" ]]; then
    if grep -q "eslint" package.json 2>/dev/null; then
        RESULT=$(npx eslint --no-warn-ignored "$FILE" 2>&1 | tail -3)
        [[ $? -ne 0 ]] && echo "ESLint issues in $(basename "$FILE"):" >&2 && echo "$RESULT" >&2
    fi
fi
exit 0
