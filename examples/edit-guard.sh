#!/bin/bash
# edit-guard.sh — Block Edit/Write to protected files
#
# Solves: PreToolUse deny being ignored for Edit/Write tools (#37210)
# Uses chmod as defense-in-depth — makes file read-only before deny
#
# GitHub Issue: #37210
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/edit-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-edit-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [edit-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only check Edit and Write tools
if [[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]]; then
    exit 0
fi

# Define protected patterns (customize these)
PROTECTED_PATTERNS=(
    "*.env*"
    "*credentials*"
    "*secrets*"
    "*.pem"
    "*.key"
    "*/.claude/settings.json"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
    if [[ "$FILE" == $pattern ]]; then
        # Defense-in-depth: make file read-only
        chmod 444 "$FILE" 2>/dev/null
        echo "BLOCKED: Edit/Write denied for protected file: $FILE" >&2
        exit 2
    fi
done

exit 0
