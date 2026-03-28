INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
if echo "$FILE" | grep -qE 'nuxt\.config\.(ts|js|mjs)$'; then
    echo "NOTE: nuxt.config modified. Dev server restart required." >&2
fi
exit 0
