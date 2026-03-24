#!/bin/bash
# ================================================================
# uncommitted-work-guard.sh — Block destructive git when dirty
# ================================================================
# PURPOSE:
#   Claude sometimes runs git checkout --, git reset --hard, or
#   git stash drop when there are uncommitted changes, destroying
#   hours of work. This hook checks git status before allowing
#   destructive git commands.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Born from: https://github.com/anthropics/claude-code/issues/37888
#   "Claude runs forbidden destructive git commands, destroys work twice"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check destructive git commands
DESTRUCTIVE=0
echo "$COMMAND" | grep -qE '\bgit\s+checkout\s+--\s' && DESTRUCTIVE=1
echo "$COMMAND" | grep -qE '\bgit\s+checkout\s+\.\s*$' && DESTRUCTIVE=1
echo "$COMMAND" | grep -qE '\bgit\s+restore\s+--staged\s+\.' && DESTRUCTIVE=1
echo "$COMMAND" | grep -qE '\bgit\s+restore\s+\.\s*$' && DESTRUCTIVE=1
echo "$COMMAND" | grep -qE '\bgit\s+reset\s+--hard' && DESTRUCTIVE=1
echo "$COMMAND" | grep -qE '\bgit\s+clean\s+-[a-zA-Z]*f' && DESTRUCTIVE=1
echo "$COMMAND" | grep -qE '\bgit\s+stash\s+drop' && DESTRUCTIVE=1

[ "$DESTRUCTIVE" -eq 0 ] && exit 0

# Check for uncommitted changes
DIRTY=$(git status --porcelain 2>/dev/null | head -20)
if [ -n "$DIRTY" ]; then
    COUNT=$(echo "$DIRTY" | wc -l)
    echo "BLOCKED: Destructive git command with $COUNT uncommitted change(s)." >&2
    echo "Changes that would be lost:" >&2
    echo "$DIRTY" | head -10 | sed 's/^/  /' >&2
    [ "$COUNT" -gt 10 ] && echo "  ... and $((COUNT-10)) more" >&2
    echo "" >&2
    echo "Commit or stash your changes first, then retry." >&2
    exit 2
fi

exit 0
