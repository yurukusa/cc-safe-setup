#!/bin/bash
# plugin-process-cleanup.sh — Kill leaked plugin subprocesses on session end
#
# Solves: Channel plugin subprocesses (bun server.ts) leak across sessions,
#         accumulating to 1000%+ CPU usage (#39137). Each session spawns
#         new processes but never kills old ones.
#
# How it works: SessionEnd hook that finds and kills plugin server processes
#   that are still running from the Claude plugins cache directory.
#
# TRIGGER: SessionEnd
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "SessionEnd": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/plugin-process-cleanup.sh" }]
#     }]
#   }
# }

# Find plugin server processes from Claude's cache
PLUGIN_CACHE="$HOME/.claude/plugins/cache"

# Kill bun/node server processes from plugin directories
PIDS=$(pgrep -f "$PLUGIN_CACHE" 2>/dev/null)

if [ -n "$PIDS" ]; then
    COUNT=$(echo "$PIDS" | wc -l | tr -d ' ')
    echo "Cleaning up $COUNT leaked plugin process(es)..." >&2

    for pid in $PIDS; do
        # Try graceful shutdown first
        kill "$pid" 2>/dev/null
    done

    # Wait briefly for graceful shutdown
    sleep 1

    # Force kill any remaining
    for pid in $PIDS; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
            echo "  Force-killed PID $pid" >&2
        fi
    done
fi

exit 0
