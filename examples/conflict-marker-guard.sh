#!/bin/bash
# ================================================================
# conflict-marker-guard.sh — Block commits with conflict markers
# ================================================================
# PURPOSE:
#   Claude sometimes resolves merge conflicts incorrectly, leaving
#   <<<<<<< / ======= / >>>>>>> markers in files. This hook checks
#   staged files for conflict markers before allowing a commit.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check on git commit
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Check staged files for conflict markers
CONFLICTS=$(git diff --cached --name-only 2>/dev/null | while read -r f; do
    [ -f "$f" ] && grep -lE '^(<{7}|={7}|>{7})' "$f" 2>/dev/null
done)

if [ -n "$CONFLICTS" ]; then
    COUNT=$(echo "$CONFLICTS" | wc -l)
    echo "BLOCKED: $COUNT file(s) contain merge conflict markers:" >&2
    echo "$CONFLICTS" | head -5 | sed 's/^/  /' >&2
    echo "" >&2
    echo "Resolve conflicts before committing." >&2
    exit 2
fi

exit 0
