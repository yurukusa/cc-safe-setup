#!/bin/bash
# ================================================================
# no-global-install.sh — Block global package installations
# ================================================================
# PURPOSE:
#   Claude often runs `npm install -g`, `pip install --user`, or
#   `gem install` without realizing these modify the global system.
#   Global installs can break other projects and are hard to undo.
#
#   This hook blocks global installations and suggests local
#   alternatives (npx, devDependencies, virtualenv).
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(*install*)",
#         "command": "~/.claude/hooks/no-global-install.sh"
#       }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# npm global install
if echo "$COMMAND" | grep -qE 'npm\s+install\s+(-g|--global)\b'; then
    PKG=$(echo "$COMMAND" | grep -oE 'npm\s+install\s+(-g|--global)\s+\S+' | awk '{print $NF}')
    echo "BLOCKED: Global npm install ($PKG)" >&2
    echo "  Use 'npx $PKG' for one-time use, or add to devDependencies." >&2
    exit 2
fi

# pip global install (without venv active)
if echo "$COMMAND" | grep -qE 'pip3?\s+install\s' && ! echo "$COMMAND" | grep -qE 'pip3?\s+install\s+(-r|--requirement)\s'; then
    if ! echo "$COMMAND" | grep -qE '(venv|virtualenv|\.venv|conda)'; then
        # Check if in a virtualenv
        if [ -z "$VIRTUAL_ENV" ] && [ ! -f "venv/bin/activate" ] && [ ! -f ".venv/bin/activate" ]; then
            echo "⚠ pip install outside virtualenv detected." >&2
            echo "  Consider using: python -m venv .venv && source .venv/bin/activate" >&2
            # Warning only (exit 0), not a hard block
        fi
    fi
fi

# gem install (system-wide)
if echo "$COMMAND" | grep -qE '^\s*sudo\s+gem\s+install'; then
    echo "BLOCKED: System-wide gem install with sudo." >&2
    echo "  Use 'bundle add' for project-local gems." >&2
    exit 2
fi

exit 0
