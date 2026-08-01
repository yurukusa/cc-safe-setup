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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-console-log-commit-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-console-log-commit]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
