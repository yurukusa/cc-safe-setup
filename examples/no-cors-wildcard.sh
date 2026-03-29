#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
if grep -qP "origin:\s*['\"]?\*['\"]?|Access-Control-Allow-Origin.*\*|cors\(\)" "$FILE" 2>/dev/null; then
    echo "WARNING: Wildcard CORS origin in $(basename "$FILE")." >&2
    echo "cors(*) allows any website to call your API." >&2
    echo "Specify allowed origins explicitly." >&2
fi
exit 0
