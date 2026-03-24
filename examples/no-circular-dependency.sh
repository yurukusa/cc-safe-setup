FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$FILE" in *package.json) ;; *) exit 0;; esac
CONTENT=$(cat | jq -r '.tool_input.new_string // empty' 2>/dev/null)
echo "$CONTENT" | grep -q "peerDependencies" && echo "NOTE: Check for circular peer deps" >&2
exit 0
