#!/bin/bash
# kill-process-guard.sh — Block dangerous process termination commands
#
# Solves: Claude Code killing important system processes or user processes
#         without understanding their purpose. kill -9 is especially dangerous
#         as it prevents graceful shutdown and can cause data corruption.
#
# Detects:
#   kill -9 <pid>        (forced termination, no cleanup)
#   killall <name>       (kills ALL matching processes)
#   pkill <pattern>      (pattern-based kill, can be too broad)
#   kill -KILL           (same as -9)
#
# Does NOT block:
#   kill <pid>           (graceful SIGTERM, allows cleanup)
#   kill -15 <pid>       (explicit SIGTERM)
#   kill -INT            (Ctrl+C equivalent)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-kill-process-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [kill-process-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block kill -9 (SIGKILL — no cleanup, potential data corruption)
if echo "$COMMAND" | grep -qE '\bkill\s+-(9|KILL)\b'; then
    echo "BLOCKED: kill -9 forces immediate termination without cleanup." >&2
    echo "  Data corruption is possible. Use 'kill <pid>' (SIGTERM) instead." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

# Block killall (kills ALL matching processes)
if echo "$COMMAND" | grep -qE '\bkillall\s'; then
    echo "BLOCKED: killall terminates ALL processes matching the name." >&2
    echo "  This may kill unrelated processes. Use 'kill <specific-pid>' instead." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

# Block pkill (pattern-based, can be overly broad)
if echo "$COMMAND" | grep -qE '\bpkill\s'; then
    echo "BLOCKED: pkill uses pattern matching which may kill unintended processes." >&2
    echo "  Find the specific PID with 'pgrep' first, then use 'kill <pid>'." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

exit 0
