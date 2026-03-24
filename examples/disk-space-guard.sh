#!/bin/bash
# ================================================================
# disk-space-guard.sh — Warn when disk space is running low
# ================================================================
# PURPOSE:
#   Long Claude Code sessions can generate large files, logs, and
#   build artifacts. This hook warns before writes when disk space
#   is below a threshold.
#
# TRIGGER: PreToolUse  MATCHER: "Write|Bash"
#
# CONFIG:
#   CC_DISK_WARN_PCT=90  (warn at this percentage used)
# ================================================================

WARN_PCT="${CC_DISK_WARN_PCT:-90}"

# Check disk usage (percentage used on the working directory's partition)
USAGE=$(df --output=pcent . 2>/dev/null | tail -1 | tr -d ' %')
[ -z "$USAGE" ] && exit 0

if [ "$USAGE" -ge "$WARN_PCT" ]; then
    AVAIL=$(df -h --output=avail . 2>/dev/null | tail -1 | tr -d ' ')
    echo "WARNING: Disk usage is ${USAGE}% (${AVAIL} available)." >&2
    echo "Consider cleaning up build artifacts, logs, or /tmp files." >&2
fi

exit 0
