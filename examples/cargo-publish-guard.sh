INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'cargo\s+publish\b' && ! echo "$COMMAND" | grep -q "\-\-dry-run"; then
    echo "BLOCKED: cargo publish to crates.io." >&2
    echo "Command: $COMMAND" >&2
    echo "Use: cargo publish --dry-run (to test first)" >&2
    exit 2
fi
exit 0
