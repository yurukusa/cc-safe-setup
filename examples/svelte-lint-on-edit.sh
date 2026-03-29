#
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != *.svelte ]] && exit 0
if command -v npx &>/dev/null && [[ -f "package.json" ]] && grep -q "svelte-check" package.json 2>/dev/null; then
    RESULT=$(npx svelte-check --threshold error 2>&1 | tail -3)
    [[ $? -ne 0 ]] && echo "Svelte check errors:" >&2 && echo "$RESULT" >&2
fi
exit 0
