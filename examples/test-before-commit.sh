#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
STATE="/tmp/cc-tests-ran-$$"
if echo "$COMMAND" | grep -qE '^\s*(npm\s+test|npx\s+jest|pytest|python\s+-m\s+pytest|cargo\s+test|go\s+test|make\s+test|bundle\s+exec\s+rspec|mix\s+test)'; then
    echo "1" > "$STATE"
    exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
    if [ ! -f "$STATE" ] || [ "$(cat "$STATE" 2>/dev/null)" != "1" ]; then
        echo "WARNING: No test commands detected since last commit." >&2
        echo "  Run tests before committing to verify your changes." >&2
    fi
    rm -f "$STATE"
fi
exit 0
