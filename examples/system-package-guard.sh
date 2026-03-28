#!/bin/bash
# ================================================================
# system-package-guard.sh — Block system-level package installations
#
# Solves: Claude running apt-get install, brew install, or yum
# install without user awareness. System package changes affect
# the entire machine and can introduce version conflicts.
#
# Blocks: apt install, apt-get install, brew install, yum install,
#         dnf install, pacman -S, snap install
# Allows: npm install, pip install (separate hooks handle these)
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/system-package-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Detect system package manager install commands
if echo "$COMMAND" | grep -qE '(apt-get|apt|yum|dnf|pacman|zypper|apk|snap|brew)\s+(install|add)\b'; then
    PKG_MGR=$(echo "$COMMAND" | grep -oE '(apt-get|apt|yum|dnf|pacman|zypper|apk|snap|brew)')
    echo "BLOCKED: System package installation detected ($PKG_MGR)." >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "System packages affect the entire machine." >&2
    echo "Consider: use project-level package managers (npm, pip, cargo) instead." >&2
    echo "Or run manually: $COMMAND" >&2
    exit 2
fi

exit 0
