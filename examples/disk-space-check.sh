#!/bin/bash
# disk-space-check.sh — Warn if disk space is low at session start
#
# Prevents: Autonomous sessions crashing due to disk full
#           npm install, git operations, and file writes fail silently
#           when disk space runs out during long-running sessions.
#
# Checks: root filesystem usage percentage
# Warns at: 80% (yellow), 90% (red), 95% (critical)
#
# TRIGGER: Notification
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "Notification": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/disk-space-check.sh" }]
#     }]
#   }
# }

# Only run once per session
MARKER="/tmp/cc-disk-check-$$"
[ -f "$MARKER" ] && exit 0

# Get disk usage percentage for root filesystem
USAGE=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
[ -z "$USAGE" ] && exit 0

if [ "$USAGE" -ge 95 ]; then
  echo "CRITICAL: Disk usage at ${USAGE}%. Operations may fail." >&2
  echo "  Free space immediately: docker system prune, rm tmp files" >&2
elif [ "$USAGE" -ge 90 ]; then
  echo "WARNING: Disk usage at ${USAGE}%. Consider freeing space." >&2
elif [ "$USAGE" -ge 80 ]; then
  echo "NOTE: Disk usage at ${USAGE}%." >&2
fi

touch "$MARKER"
exit 0
