#!/bin/bash
# require-issue-ref.sh — Warn when commit message lacks issue reference
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
    MSG=$(echo "$COMMAND" | grep -oP "\-m\s+['\"]?\K[^'\"]+")
    if [ -n "$MSG" ]; then
        if ! echo "$MSG" | grep -qE '#[0-9]+|[A-Z]+-[0-9]+'; then
            echo "WARNING: Commit message has no issue reference (#123 or PROJ-123)." >&2
            echo "Consider linking to an issue for traceability." >&2
        fi
    fi
fi
exit 0
