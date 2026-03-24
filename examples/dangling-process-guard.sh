#!/bin/bash
# ================================================================
# dangling-process-guard.sh — Detect background processes left running
# ================================================================
# PURPOSE:
#   Claude starts dev servers, watchers, and long-running processes
#   with & or nohup. These persist after the session ends, consuming
#   resources and ports. This Stop hook lists any processes started
#   in the current directory.
#
# TRIGGER: Stop  MATCHER: ""
# ================================================================

# Find processes with CWD matching current directory
CWD=$(pwd)
PROCS=$(ps aux 2>/dev/null | grep -v grep | grep "$CWD" | grep -vE '(claude|node.*cc-safe)' | head -5)

if [ -n "$PROCS" ]; then
    COUNT=$(echo "$PROCS" | wc -l)
    echo "" >&2
    echo "NOTE: $COUNT process(es) still running in $CWD:" >&2
    echo "$PROCS" | awk '{print "  PID " $2 ": " $11}' >&2
    echo "Kill with: kill \$(lsof -t -i :PORT) or kill PID" >&2
fi

exit 0
