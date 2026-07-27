#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '(git\s+commit|git\s+push|husky|lint-staged|pre-commit)' || exit 0
if [ -d ".git/hooks" ]; then
    ACTIVE=$(find .git/hooks -maxdepth 1 -type f -executable ! -name "*.sample" 2>/dev/null | wc -l)
    if [ "$ACTIVE" -gt 0 ]; then
        echo "NOTE: $ACTIVE active git hooks found in .git/hooks/" >&2
        echo "Ensure CC hooks and git hooks don't duplicate checks." >&2
    fi
fi
if [ -d ".husky" ]; then
    HUSKY=$(find .husky -maxdepth 1 -type f -executable 2>/dev/null | wc -l)
    if [ "$HUSKY" -gt 0 ]; then
        echo "NOTE: Husky detected with $HUSKY hooks. CC hooks run separately." >&2
    fi
fi
exit 0
