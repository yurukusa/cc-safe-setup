INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in
    */.claude/hooks/*.sh|*/hooks/*.sh) ;;
    *) exit 0 ;;
esac
[ ! -f "$FILE" ] && exit 0
if grep -qE '^\s*sleep\s+[0-9]' "$FILE" 2>/dev/null; then
    echo "WARNING: Hook contains sleep command: $FILE" >&2
    echo "Sleep in hooks causes Claude Code to hang or timeout." >&2
    echo "Remove sleep calls or use non-blocking alternatives." >&2
fi
exit 0
