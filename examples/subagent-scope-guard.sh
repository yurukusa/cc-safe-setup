#!/bin/bash
# ================================================================
# subagent-scope-guard.sh — Limit subagent file access scope
# ================================================================
# PURPOSE:
#   In multi-agent setups, subagents should only modify files
#   within their assigned directory. This hook reads a scope
#   file (.claude/agent-scope.txt) and blocks writes outside it.
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
#
# Setup: echo "src/auth/" > .claude/agent-scope.txt
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-subagent-scope-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [subagent-scope-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

SCOPE_FILE=".claude/agent-scope.txt"
[ -f "$SCOPE_FILE" ] || exit 0

SCOPE=$(cat "$SCOPE_FILE" | head -1 | tr -d '\n')
[ -z "$SCOPE" ] && exit 0

# Check if file is within scope
case "$FILE" in
    ${SCOPE}*) exit 0 ;;  # Within scope
    *)
        echo "BLOCKED: File $FILE is outside agent scope ($SCOPE)." >&2
        echo "This agent should only modify files under $SCOPE" >&2
        exit 2
        ;;
esac
