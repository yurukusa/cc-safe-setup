#!/bin/bash
# ================================================================
# no-console-log-commit.sh — Block commits containing console.log
# ================================================================
# PURPOSE:
#   Claude often adds console.log for debugging and forgets to
#   remove them before committing. This hook checks staged changes
#   for console.log/console.debug/console.warn and blocks the commit.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(git commit*)",
#         "command": "~/.claude/hooks/no-console-log-commit.sh"
#       }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git commit commands
echo "$COMMAND" | grep -qE '^\s*git\s+commit\b' || exit 0

# Check staged diff for console.log
STAGED=$(git diff --cached --diff-filter=ACM -- '*.js' '*.jsx' '*.ts' '*.tsx' 2>/dev/null)
if echo "$STAGED" | grep -qE '^\+.*console\.(log|debug)\('; then
    COUNT=$(echo "$STAGED" | grep -cE '^\+.*console\.(log|debug)\(')
    echo "BLOCKED: $COUNT console.log/debug statement(s) in staged changes." >&2
    echo "  Remove debug logging before committing." >&2
    exit 2
fi

exit 0
