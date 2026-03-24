#!/bin/bash
# readme-update-reminder.sh — Remind to update README when APIs change
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
# Check if API-related files changed but README didn't
API_FILES=$(git diff --cached --name-only 2>/dev/null | grep -cE '(routes|api|endpoint|handler|controller)' || echo 0)
README_CHANGED=$(git diff --cached --name-only 2>/dev/null | grep -c 'README' || echo 0)
if [ "$API_FILES" -gt 0 ] && [ "$README_CHANGED" -eq 0 ]; then
    echo "NOTE: API files changed but README was not updated." >&2
    echo "Consider updating API documentation." >&2
fi
exit 0
