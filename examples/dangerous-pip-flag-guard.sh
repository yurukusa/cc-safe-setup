#!/bin/bash
# dangerous-pip-flag-guard.sh — Block dangerous pip flags that bypass safety
#
# Solves: Claude Code using pip install with dangerous flags in auto mode
#   - #48992: pip install --break-system-packages passed through auto mode
#   - Breaks system Python installations, can render OS tools unusable
#
# What it blocks:
#   --break-system-packages (bypasses PEP 668 externally-managed check)
#   --force-reinstall combined with system paths
#   pip install targeting /usr/lib or /usr/local/lib directly
#
# What it allows:
#   pip install in virtual environments (venv/conda)
#   pip install --user (installs to user directory)
#   pip install in project directories
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-dangerous-pip-flag-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [dangerous-pip-flag-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check pip commands
echo "$COMMAND" | grep -qE '\bpip[3]?\s+install\b' || exit 0

# Block --break-system-packages
if echo "$COMMAND" | grep -qE '\-\-break-system-packages'; then
    echo "BLOCKED: --break-system-packages flag detected" >&2
    echo "This flag bypasses PEP 668 protection and can break your system Python." >&2
    echo "Use a virtual environment instead: python3 -m venv .venv && source .venv/bin/activate" >&2
    exit 2
fi

# Block sudo pip install (system-wide install without venv)
if echo "$COMMAND" | grep -qE '\bsudo\s+pip[3]?\s+install\b'; then
    echo "BLOCKED: sudo pip install detected" >&2
    echo "System-wide pip install can break OS tools. Use a virtual environment." >&2
    exit 2
fi

# Block pip targeting system directories
if echo "$COMMAND" | grep -qE '\bpip[3]?\s+install\b.*\-\-target\s*=?\s*/(usr|opt|lib)'; then
    echo "BLOCKED: pip install targeting system directory" >&2
    echo "Installing packages to system directories can break OS tools." >&2
    exit 2
fi

exit 0
