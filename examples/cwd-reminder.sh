#!/bin/bash
# cwd-reminder.sh — Remind Claude of the current working directory
#
# Solves: Claude loses track of which directory it's in (#1669 — 71 reactions)
#         Can lead to commands running in wrong directory, including
#         destructive operations like git reset in the wrong repo.
#
# Emits the current working directory to stderr before every Bash command,
# making it visible in the tool output so Claude always knows where it is.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/cwd-reminder.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Don't add noise to empty commands
[ -z "$COMMAND" ] && exit 0

# Get the working directory from the tool input if available,
# otherwise use the process's cwd
CWD=$(echo "$INPUT" | jq -r '.tool_input.working_directory // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD=$(pwd)

echo "[cwd: $CWD]" >&2

exit 0
