#!/bin/bash
# plain-language-danger-warn.sh — Add plain-language warnings to dangerous commands
#
# Solves: Users not understanding technical risk of commands (#30505).
#         "git reset --hard" doesn't convey "this deletes all your unsaved work."
#
# How it works: PreToolUse hook on Bash that detects dangerous commands
#   and injects plain-language explanations into stderr context.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Map dangerous commands to plain-language warnings
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  echo "WARNING: This will DELETE all unsaved changes in your working directory." >&2
  echo "Any uncommitted work will be permanently lost." >&2
elif echo "$COMMAND" | grep -qE 'git\s+clean\s+-[fd]'; then
  echo "WARNING: This will DELETE all untracked files (files not in git)." >&2
elif echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force'; then
  echo "WARNING: This will OVERWRITE the remote branch history." >&2
  echo "Other people's commits may be permanently lost." >&2
elif echo "$COMMAND" | grep -qE 'rm\s+-rf\s+/'; then
  echo "WARNING: This will DELETE everything on the system. Unrecoverable." >&2
elif echo "$COMMAND" | grep -qE 'drop\s+(database|table|schema)'; then
  echo "WARNING: This will DELETE the entire database/table. Data is unrecoverable." >&2
elif echo "$COMMAND" | grep -qE 'truncate\s+table'; then
  echo "WARNING: This will DELETE all rows in the table." >&2
fi

# Always allow — this hook only warns, doesn't block
exit 0
