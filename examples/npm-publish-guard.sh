#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*(npm\s+publish|npx\s+npm\s+publish)'; then
    if [ -f "package.json" ]; then
        VER=$(python3 -c "import json; print(json.load(open('package.json')).get('version','?'))" 2>/dev/null)
        echo "BLOCKED: npm publish of version $VER requires manual confirmation." >&2
    else
        echo "BLOCKED: npm publish requires manual confirmation." >&2
    fi
    exit 2
fi
exit 0
