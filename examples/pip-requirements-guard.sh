#!/bin/bash
# pip-requirements-guard.sh — Enforce pip install from requirements.txt only
#
# Solves: Claude Code installing arbitrary Python packages with pip install
#         instead of using the project's requirements.txt or pyproject.toml.
#         Random package installs can introduce vulnerabilities and break
#         reproducible builds.
#
# Detects:
#   pip install <package>        (direct package install)
#   pip3 install <package>       (same)
#   python -m pip install <pkg>  (module invocation)
#
# Does NOT block:
#   pip install -r requirements.txt  (from requirements file)
#   pip install -e .                 (editable install of current project)
#   pip install --upgrade pip        (pip self-upgrade)
#   pip list / pip show             (read-only)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only check pip install commands
echo "$COMMAND" | grep -qE '\bpip3?\s+install\b|python3?\s+-m\s+pip\s+install\b' || exit 0

# Allow requirements file installs
echo "$COMMAND" | grep -qE 'pip3?\s+install\s+-r\s' && exit 0

# Allow editable installs
echo "$COMMAND" | grep -qE 'pip3?\s+install\s+-e\s' && exit 0

# Allow pip self-upgrade
echo "$COMMAND" | grep -qE 'pip3?\s+install\s+--upgrade\s+pip\b' && exit 0

# Block direct package installs
echo "BLOCKED: Direct pip install detected." >&2
echo "  Use 'pip install -r requirements.txt' for reproducible builds." >&2
echo "  Command: $COMMAND" >&2
exit 2
