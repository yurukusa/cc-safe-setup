#!/bin/bash
# pip-venv-guard.sh — Warn when pip install runs outside a virtual environment
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*pip\s+install' || exit 0
if [ -z "$VIRTUAL_ENV" ] && [ ! -d ".venv" ] && [ ! -d "venv" ]; then
  echo "WARNING: pip install without active virtual environment." >&2
  echo "Packages will be installed system-wide." >&2
  echo "Create a venv: python -m venv .venv && source .venv/bin/activate" >&2
fi
exit 0
