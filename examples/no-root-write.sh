#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-root-write-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-root-write]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in /etc/*|/usr/*|/bin/*|/sbin/*|/boot/*|/sys/*|/proc/*)
    echo "BLOCKED: Write to system directory" >&2; exit 2 ;; esac
exit 0
