#!/bin/bash
# npm-global-install-guard.sh — Block npm global installs
#
# Solves: Claude Code running npm install -g which modifies the global
#         node_modules directory. Global installs can conflict with
#         system tools and affect all projects.
#
# Detects:
#   npm install -g <package>
#   npm i -g <package>
#   npm install --global <package>
#
# Does NOT block:
#   npm install (local)
#   npx <package> (temporary execution)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

if echo "$COMMAND" | grep -qE '\bnpm\s+(install|i)\s+(-g|--global)\b'; then
    echo "BLOCKED: npm global install modifies system-wide packages." >&2
    echo "  Use 'npx <package>' for one-time execution instead." >&2
    echo "  Or install locally: 'npm install --save-dev <package>'" >&2
    exit 2
fi

exit 0
