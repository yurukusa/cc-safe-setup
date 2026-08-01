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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-pip-venv-required-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [pip-venv-required]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
