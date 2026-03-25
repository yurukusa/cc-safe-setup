INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit\b' || exit 0
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
MAX=${CC_MAX_COMMIT_FILES:-20}
if [ "$STAGED" -gt "$MAX" ]; then
    echo "WARNING: Committing $STAGED files (threshold: $MAX)." >&2
    echo "Consider splitting into smaller, focused commits." >&2
    echo "Staged files:" >&2
    git diff --cached --name-only 2>/dev/null | head -10 >&2
    [ "$STAGED" -gt 10 ] && echo "... and $((STAGED - 10)) more" >&2
fi
exit 0
