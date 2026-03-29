#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.md|*.txt|*.log) exit 0 ;; esac
IPS=$(grep -nP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' "$FILE" 2>/dev/null | grep -v '127\.0\.0\.1\|0\.0\.0\.0\|localhost\|example' | head -3)
if [[ -n "$IPS" ]]; then
    echo "WARNING: Hardcoded IP address in $(basename "$FILE"):" >&2
    echo "$IPS" >&2
    echo "Consider: use env vars or config files for IPs." >&2
fi
exit 0
