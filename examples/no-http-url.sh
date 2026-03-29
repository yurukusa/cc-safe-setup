#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.md|*.txt|*.log) exit 0 ;; esac
HTTP=$(grep -nP 'http://(?!localhost|127\.0\.0\.1|0\.0\.0\.0|example\.com)' "$FILE" 2>/dev/null | head -3)
if [[ -n "$HTTP" ]]; then
    echo "WARNING: Non-HTTPS URL in $(basename "$FILE"):" >&2
    echo "$HTTP" >&2
    echo "Use https:// for security." >&2
fi
exit 0
