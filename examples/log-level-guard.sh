INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
FILE=$(echo "$INPUT" | jq -r ".tool_input.file_path // empty" 2>/dev/null); case "$FILE" in *test*|*spec*|*debug*) exit 0;; esac; echo "$CONTENT" | grep -qE "log\.debug|LOG_LEVEL.*DEBUG|logging\.DEBUG" && echo "NOTE: Debug logging in production code" >&2
exit 0
