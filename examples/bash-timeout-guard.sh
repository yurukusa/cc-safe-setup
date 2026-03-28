#!/bin/bash
# ================================================================
# bash-timeout-guard.sh — Warn on commands likely to hang or run
# indefinitely without a timeout
#
# Solves: Claude running commands that hang forever (e.g., servers,
# watchers, interactive tools) causing the session to stall.
# Common pattern: `npm start`, `python app.py`, `tail -f`,
# `docker logs -f`, or `while true` loops.
#
# This hook warns (but doesn't block) when a command looks like
# it will run indefinitely, suggesting `timeout` prefix.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/bash-timeout-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Already has timeout — good
if echo "$COMMAND" | grep -qE '^\s*timeout\s'; then
    exit 0
fi

# Detect commands that typically run forever
INFINITE=0
REASON=""

# Server/watcher start commands
if echo "$COMMAND" | grep -qE '(npm|yarn|pnpm)\s+(start|run\s+dev|run\s+serve)'; then
    INFINITE=1; REASON="dev server (runs indefinitely)"
elif echo "$COMMAND" | grep -qE 'python\s+.*\b(app|server|manage\.py\s+runserver|flask\s+run|uvicorn|gunicorn)'; then
    INFINITE=1; REASON="Python server"
elif echo "$COMMAND" | grep -qE 'node\s+.*\b(server|app|index)\b'; then
    INFINITE=1; REASON="Node.js server"
elif echo "$COMMAND" | grep -qE '(tail|docker\s+logs)\s+-f'; then
    INFINITE=1; REASON="follow mode (runs indefinitely)"
elif echo "$COMMAND" | grep -qE 'while\s+(true|:|\[\s*1\s*\])'; then
    INFINITE=1; REASON="infinite loop"
elif echo "$COMMAND" | grep -qE '(nc|netcat|ncat)\s+.*-l'; then
    INFINITE=1; REASON="network listener"
elif echo "$COMMAND" | grep -qE 'inotifywait|fswatch|watchman'; then
    INFINITE=1; REASON="file watcher"
fi

if [[ "$INFINITE" -eq 1 ]]; then
    echo "WARNING: This command may run indefinitely ($REASON)." >&2
    echo "Command: $COMMAND" >&2
    echo "Consider: timeout 30 $COMMAND" >&2
fi

exit 0
