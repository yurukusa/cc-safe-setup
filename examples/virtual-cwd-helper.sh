#!/bin/bash
# virtual-cwd-helper.sh — Remind about virtual working directory
#
# Solves: Claude Code is bound to the directory where it was
#         spawned. Users can't switch projects mid-session (#3473).
#
# How it works: Reads ~/.claude/virtual-cwd file. If set,
#   warns that commands should be prefixed with cd to the
#   virtual CWD. Users can switch directories by updating
#   the file.
#
# Setup: echo "/path/to/project" > ~/.claude/virtual-cwd
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail
INPUT=$(cat)

VCWD_FILE="${HOME}/.claude/virtual-cwd"
[ ! -f "$VCWD_FILE" ] && exit 0

VCWD=$(cat "$VCWD_FILE" 2>/dev/null)
[ -z "$VCWD" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Skip if command already starts with cd to the virtual CWD
if echo "$COMMAND" | grep -q "^cd $VCWD"; then
  exit 0
fi

# Skip cd commands (user is navigating)
if echo "$COMMAND" | grep -q "^cd "; then
  exit 0
fi

echo "NOTE: Virtual CWD is $VCWD — prefix with: cd $VCWD &&" >&2
exit 0
