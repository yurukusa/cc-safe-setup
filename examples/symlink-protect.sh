INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]] && exit 0
if [ -L "$FILE" ]; then
    TARGET=$(readlink -f "$FILE")
    echo "NOTE: Redirecting write from symlink $FILE → $TARGET" >&2
    echo "{\"updatedInput\":{\"file_path\":\"$TARGET\"}}"
    exit 1
fi
exit 0
