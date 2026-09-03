#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-gem-push-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [gem-push-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'gem\s+push\b'; then
    echo "BLOCKED: gem push to RubyGems.org." >&2
    echo "Command: $COMMAND" >&2
    echo "Publishing packages should be done manually." >&2
    exit 2
fi
exit 0
