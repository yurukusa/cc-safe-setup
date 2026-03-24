COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*npm\s+publish'; then
    if [ -f "package.json" ]; then
        VER=$(python3 -c "import json; print(json.load(open('package.json')).get('version','?'))" 2>/dev/null)
        echo "NOTE: Publishing version $VER to npm." >&2
    fi
fi
exit 0
