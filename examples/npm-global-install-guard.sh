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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-npm-global-install-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [npm-global-install-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
