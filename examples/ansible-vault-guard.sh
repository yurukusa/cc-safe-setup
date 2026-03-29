#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'ansible-vault\s+decrypt\b'; then
    echo "WARNING: Decrypting Ansible vault." >&2
    echo "Remember to re-encrypt before committing." >&2
fi
exit 0
