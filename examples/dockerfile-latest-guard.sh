INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
if ! echo "$FILE" | grep -qiE 'Dockerfile'; then exit 0; fi
LATEST=$(grep -nP '^FROM\s+\S+:latest\b' "$FILE" 2>/dev/null | head -3)
if [[ -n "$LATEST" ]]; then
    echo "WARNING: :latest tag in Dockerfile:" >&2
    echo "$LATEST" >&2
    echo "Pin to a specific version for reproducible builds." >&2
fi
exit 0
