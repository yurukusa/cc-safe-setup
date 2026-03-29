#!/bin/bash
# tmp-output-size-guard.sh — Monitor and warn about large tmp output files
#
# Solves: Task .output files in /tmp grow unbounded (95GB+) filling disk
#         (#39909). Subagent output aggregation can create multi-GB files.
#
# How it works: Notification/SessionStart hook that checks /tmp for large
#   Claude Code output files and warns if any exceed a threshold.
#   Also provides a cleanup command suggestion.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/tmp-output-size-guard.sh" }]
#     }]
#   }
# }

# Configurable threshold in MB
THRESHOLD_MB="${CC_TMP_THRESHOLD_MB:-500}"

# Find Claude Code tmp directories
TMP_BASE="/tmp/claude-$(id -u)"
[ -d "/private/tmp/claude-$(id -u)" ] && TMP_BASE="/private/tmp/claude-$(id -u)"
[ ! -d "$TMP_BASE" ] && exit 0

# Find files over threshold
LARGE_FILES=$(find "$TMP_BASE" -name "*.output" -size "+${THRESHOLD_MB}M" 2>/dev/null)
[ -z "$LARGE_FILES" ] && exit 0

TOTAL_SIZE=$(echo "$LARGE_FILES" | xargs du -sh 2>/dev/null | awk '{sum+=$1} END {print sum}')
FILE_COUNT=$(echo "$LARGE_FILES" | wc -l | tr -d ' ')

echo "⚠ Found $FILE_COUNT large task output file(s) in $TMP_BASE (>${THRESHOLD_MB}MB each):" >&2
echo "$LARGE_FILES" | while read f; do
    SIZE=$(du -sh "$f" 2>/dev/null | cut -f1)
    echo "  $SIZE  $(basename "$f")" >&2
done
echo "" >&2
echo "To clean up: find $TMP_BASE -name '*.output' -size +${THRESHOLD_MB}M -delete" >&2

exit 0
