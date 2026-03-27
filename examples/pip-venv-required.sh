#!/bin/bash
# pip-venv-required.sh — Block pip install outside of a virtual environment
#
# Prevents: System-wide pip install that can break the OS Python.
#           Only allows pip install when a virtualenv is active.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/pip-venv-required.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check pip install commands
echo "$COMMAND" | grep -qE '^\s*(pip|pip3)\s+install' || exit 0

# Allow if -r requirements.txt (deterministic install)
echo "$COMMAND" | grep -qE 'pip3?\s+install\s+-r' && exit 0

# Allow if --user flag (user-level, not system)
echo "$COMMAND" | grep -qE 'pip3?\s+install\s+.*--user' && exit 0

# Check if virtualenv is active
if [ -z "$VIRTUAL_ENV" ] && [ -z "$CONDA_DEFAULT_ENV" ]; then
  echo "BLOCKED: pip install outside of virtual environment." >&2
  echo "  Activate a venv first: python3 -m venv .venv && source .venv/bin/activate" >&2
  exit 2
fi

exit 0
