INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.js|*.py|*.java|*.go|*.rs) ;; *) exit 0 ;; esac
MAGICS=$(grep -nP '(?<!\w)\d{4,}(?!\w)' "$FILE" 2>/dev/null | grep -v 'port\|PORT\|timeout\|TIMEOUT\|1000\|3000\|5000\|8000\|8080\|9090' | head -3)
if [[ -n "$MAGICS" ]]; then
    echo "NOTE: Possible magic numbers in $(basename "$FILE"):" >&2
    echo "$MAGICS" >&2
    echo "Consider: extract to named constants." >&2
fi
exit 0
