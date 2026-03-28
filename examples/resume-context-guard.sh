#!/bin/bash
# resume-context-guard.sh — Warn when resuming large sessions
#
# Solves: Session resume on large contexts causes token explosion.
#         Users reported $342 in tokens consumed on resume with no input (#38029).
#         Large sessions (>100 tool calls) should be compacted before resume.
#
# How it works: Notification hook on SessionStart. Checks if a session
#               counter file exists (indicating a resumed session) and if
#               the counter is above threshold, warns to /compact first.
#
# TRIGGER: Notification  MATCHER: ""
# ================================================================

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.type // empty' 2>/dev/null)

# Only act on session-related events
[ -z "$EVENT" ] && exit 0

# Check for existing session state (indicates resume)
STATE="/tmp/cc-tool-count-$(echo "$PWD" | md5sum | cut -c1-8)"

if [ -f "$STATE" ]; then
    COUNT=$(cat "$STATE" 2>/dev/null || echo "0")
    THRESHOLD="${CC_RESUME_WARN:-100}"

    if [ "$COUNT" -gt "$THRESHOLD" ]; then
        echo "" >&2
        echo "⚠ LARGE SESSION DETECTED: $COUNT tool calls in previous session." >&2
        echo "Resuming large sessions can cause token explosion (~$342 reported in #38029)." >&2
        echo "Recommendation: Run /compact early to reduce context size." >&2
        echo "Or start a new session: claude" >&2
    fi
fi

exit 0
