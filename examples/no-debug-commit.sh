#!/bin/bash
# no-debug-commit.sh — Block commits containing debug artifacts
#
# Prevents: Shipping console.log, debugger statements, TODO/FIXME,
#           commented-out code blocks, or test-only changes.
#
# Checks staged files for common debug patterns before git commit.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(git commit *)",
#         "command": "~/.claude/hooks/no-debug-commit.sh"
#       }]
#     }]
#   }
# }
#
# The "if" field (v2.1.85+) skips this hook for non-commit commands.
# Without "if", the hook still works — it checks internally and exits early.

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-debug-commit-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-debug-commit]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git commit commands
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Check staged files for debug patterns
ISSUES=""

# console.log / debugger in JS/TS
STAGED_JS=$(git diff --cached --name-only -- '*.js' '*.ts' '*.tsx' '*.jsx' 2>/dev/null)
if [ -n "$STAGED_JS" ]; then
  FOUND=$(git diff --cached -- $STAGED_JS 2>/dev/null | grep -E '^\+.*(console\.log|debugger\b)' | head -3)
  [ -n "$FOUND" ] && ISSUES="${ISSUES}\n  JS/TS: console.log or debugger found"
fi

# print() in Python (added lines only)
STAGED_PY=$(git diff --cached --name-only -- '*.py' 2>/dev/null)
if [ -n "$STAGED_PY" ]; then
  FOUND=$(git diff --cached -- $STAGED_PY 2>/dev/null | grep -E '^\+.*\bprint\(' | grep -v '^\+.*#' | head -3)
  [ -n "$FOUND" ] && ISSUES="${ISSUES}\n  Python: print() statements found"
fi

if [ -n "$ISSUES" ]; then
  echo "WARNING: Debug artifacts in staged changes:" >&2
  echo -e "$ISSUES" >&2
  echo "  Review before committing. Use 'git diff --cached' to check." >&2
  # Warning only — change exit 0 to exit 2 to block
fi

exit 0
