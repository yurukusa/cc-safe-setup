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
