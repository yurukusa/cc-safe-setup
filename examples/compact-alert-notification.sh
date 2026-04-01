#!/bin/bash
# ================================================================
# compact-alert-notification.sh — Warn when compaction is imminent
# ================================================================
# PURPOSE:
#   Context compaction burns tokens to re-summarize the conversation.
#   This hook alerts you when compaction is about to happen so you
#   can use /compact or /clear proactively for a cheaper alternative.
#
# TRIGGER: Notification
# MATCHER: ""
#
# HOW IT WORKS:
#   Checks the notification message for compaction-related keywords.
#   Prints a warning to stderr (shown in the terminal) when detected.
#
# WHY THIS MATTERS:
#   Auto-compact fires at a fixed threshold. Each cycle costs tokens
#   to summarize. Manual /compact before the threshold lets you
#   control timing and reduce surprise token consumption.
#
# OUTPUT:
#   Warning message to stderr when compaction is detected.
#   Always exits 0 (notifications should never block).
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41249
#   https://github.com/anthropics/claude-code/issues/17428
# ================================================================

INPUT=$(cat)

MSG=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)

if echo "$MSG" | grep -qi "compact"; then
  echo "⚠ Context approaching limit — compaction imminent. Consider /compact or /clear now." >&2
fi

exit 0
