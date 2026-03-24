CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
FILE=$(cat | jq -r ".tool_input.file_path // empty" 2>/dev/null); case "$FILE" in *test*|*spec*) exit 0;; esac; echo "$CONTENT" | grep -qE "console\.(log|warn)" && echo "NOTE: console statement in non-test file" >&2
exit 0
