#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+push\b' || exit 0
if [ -f "package.json" ]; then
    HAS_TEST=$(jq -r '.scripts.test // empty' package.json 2>/dev/null)
    if [ -n "$HAS_TEST" ] && [ "$HAS_TEST" != "echo \"Error: no test specified\" && exit 1" ]; then
        RECENT_TEST=0
        for marker in coverage/.last-run.json test-results junit.xml .nyc_output; do
            if [ -e "$marker" ]; then
                AGE=$(( $(date +%s) - $(stat -c %Y "$marker" 2>/dev/null || echo 0) ))
                if [ "$AGE" -lt 600 ]; then
                    RECENT_TEST=1
                    break
                fi
            fi
        done
        if [ "$RECENT_TEST" -eq 0 ]; then
            echo "WARNING: Pushing without recent test run." >&2
            echo "Run 'npm test' before pushing to verify changes." >&2
        fi
    fi
fi
if [ -f "Makefile" ] && grep -q "^test:" Makefile 2>/dev/null; then
    :  # Could check make test recency, but keeping it simple
fi
exit 0
