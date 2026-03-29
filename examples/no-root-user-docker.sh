#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
if ! echo "$FILE" | grep -qiE 'Dockerfile'; then exit 0; fi
if ! grep -q '^USER\b' "$FILE" 2>/dev/null; then
    echo "NOTE: Dockerfile runs as root (no USER directive)." >&2
    echo "Add USER to run as non-root for security." >&2
fi
exit 0
