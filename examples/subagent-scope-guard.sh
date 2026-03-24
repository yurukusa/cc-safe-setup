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
