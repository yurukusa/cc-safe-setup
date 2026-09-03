#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash|PowerShell"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-cargo-publish-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [cargo-publish-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'cargo\s+publish\b' && ! echo "$COMMAND" | grep -q "\-\-dry-run"; then
    echo "BLOCKED: cargo publish to crates.io." >&2
    echo "Command: $COMMAND" >&2
    echo "Use: cargo publish --dry-run (to test first)" >&2
    exit 2
fi
exit 0
