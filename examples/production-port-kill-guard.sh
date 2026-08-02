#!/bin/bash
# production-port-kill-guard.sh — Block commands that kill processes by port number
#
# Solves: Claude Code killing production services running on ports without
#         understanding their purpose. Real incident: user's CLAUDE.md said
#         port 7000, but Claude killed the process on port 8000 — $1,000 loss.
#         (GitHub Issue #50971)
#
# Detects:
#   lsof -ti :PORT | xargs kill      (find process by port, then kill)
#   lsof -t -i :PORT | kill          (same, different flag style)
#   fuser -k PORT/tcp                (directly kill process on port)
#   fuser --kill PORT/tcp            (same, long flag)
#   kill $(lsof -ti :PORT)           (subshell variant)
#
# Does NOT block:
#   lsof -i :PORT                    (just listing, no kill)
#   fuser PORT/tcp                   (just checking, no kill)
#   netstat / ss                     (read-only port inspection)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-production-port-kill-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [production-port-kill-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block lsof-to-kill pipeline (lsof -ti :PORT piped to kill/xargs kill)
# Covers: -ti :PORT, -t -i :PORT, -i :PORT -t, and combined flags like -sti
if echo "$COMMAND" | grep -qE 'lsof\s.*-[a-zA-Z]*t.*:'; then
    if echo "$COMMAND" | grep -qE '\|\s*(xargs\s+)?kill|kill\s+\$\('; then
        PORT=$(echo "$COMMAND" | grep -oP ':\K\d+' | head -1)
        echo "BLOCKED: Killing process by port number is dangerous." >&2
        echo "  Port ${PORT} may be running a production service." >&2
        echo "  First check what's running: lsof -i :${PORT}" >&2
        echo "  Then decide manually whether to stop it." >&2
        echo "  Command: $COMMAND" >&2
        exit 2
    fi
fi

# Block kill $(lsof ...) subshell pattern
if echo "$COMMAND" | grep -qE 'kill\s+\$\(lsof\s'; then
    echo "BLOCKED: Killing process found by lsof is dangerous." >&2
    echo "  Verify the process identity before terminating." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

# Block fuser -k (directly kills process on port)
if echo "$COMMAND" | grep -qE '\bfuser\s+(-[a-zA-Z]*k|--kill)\s'; then
    PORT=$(echo "$COMMAND" | grep -oP '\d+(?=/tcp)' | head -1)
    echo "BLOCKED: fuser -k kills the process on port ${PORT:-unknown} immediately." >&2
    echo "  First check: fuser ${PORT:-PORT}/tcp" >&2
    echo "  Then stop the service gracefully if needed." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

exit 0
