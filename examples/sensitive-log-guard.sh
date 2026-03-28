INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.js|*.py|*.java|*.go|*.rb) ;; *) exit 0 ;; esac
LEAKS=$(grep -nP '(console\.log|print|log\.(info|debug|warn))\(.*\b(password|token|secret|api_key|apiKey|auth)\b' "$FILE" 2>/dev/null | head -3)
if [[ -n "$LEAKS" ]]; then
    echo "WARNING: Sensitive data may be logged in $(basename "$FILE"):" >&2
    echo "$LEAKS" >&2
    echo "Never log passwords, tokens, or API keys." >&2
fi
exit 0
