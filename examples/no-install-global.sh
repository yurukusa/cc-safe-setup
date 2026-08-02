#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-install-global-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-install-global]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE 'npm\s+install\s+-g\s|npm\s+i\s+-g\s'; then
    echo "BLOCKED: Global npm install. Use npx or local install." >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE 'sudo\s+pip\s+install|pip\s+install\s+--system'; then
    echo "BLOCKED: System-wide pip install. Use virtualenv." >&2
    exit 2
fi
exit 0
