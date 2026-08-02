#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.js|*.py|*.go|*.java) ;; *) exit 0 ;; esac
PORTS=$(grep -nE 'listen\([[:space:]]*[0-9]{4,5}[[:space:]]*\)|\.port[[:space:]]*=[[:space:]]*[0-9]{4,5}|PORT[[:space:]]*=[[:space:]]*[0-9]{4,5}' "$FILE" 2>/dev/null | grep -v 'process\.env\|os\.environ\|env\.' | head -3)
if [[ -n "$PORTS" ]]; then
    echo "NOTE: Hardcoded port in $(basename "$FILE"):" >&2
    echo "$PORTS" >&2
    echo "Consider: use PORT env var for deployment flexibility." >&2
fi
exit 0
