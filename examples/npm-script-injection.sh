CONTENT=$(cat | jq -r '.tool_input.new_string // empty' 2>/dev/null)
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
case "$FILE" in */package.json|package.json) ;; *) exit 0 ;; esac
if echo "$CONTENT" | grep -qE '"(pre|post)?(install|publish|prepare|version)".*[;&|`$]'; then
    echo "WARNING: package.json script may contain shell injection." >&2
fi
exit 0
