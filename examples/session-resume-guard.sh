#!/bin/bash
# session-resume-guard.sh — Verify context is loaded after session resume
#
# Solves: Session resume loads zero conversation history (#40319).
#         When --continue resumes a long session, cache_read_input_tokens
#         can drop from 434k to 0, silently losing all context.
#
# How it works: On SessionStart, checks if this is a resumed session
#   (via CC_RESUME or --continue flag indicators). If so, verifies that
#   key context files exist and warns if they might be stale.
#
# Also saves a "session handoff" file on Stop, so the next session
# can detect if context was properly transferred.
#
# TRIGGER: Notification (SessionStart)
# MATCHER: "" (fires on all notifications, filters for SessionStart internally)

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.event // empty' 2>/dev/null)

HANDOFF_DIR="${HOME}/.claude/handoff"
mkdir -p "$HANDOFF_DIR"
HANDOFF_FILE="${HANDOFF_DIR}/last-session.md"

case "$EVENT" in
    session_start|SessionStart)
        # Check if this is a resume (handoff file exists and is recent)
        if [ -f "$HANDOFF_FILE" ]; then
            AGE_SECONDS=$(( $(date +%s) - $(stat -c %Y "$HANDOFF_FILE" 2>/dev/null || echo 0) ))

            if [ "$AGE_SECONDS" -lt 3600 ]; then
                echo "📋 Resuming from previous session (handoff ${AGE_SECONDS}s ago)" >&2
                echo "  Last session state:" >&2
                head -5 "$HANDOFF_FILE" >&2
            else
                AGE_HOURS=$((AGE_SECONDS / 3600))
                echo "⚠ Previous session handoff is ${AGE_HOURS}h old" >&2
                echo "  Context may be stale. Consider starting fresh." >&2
            fi
        fi

        # Check for recovery snapshots (from compaction-transcript-guard)
        RECOVERY_DIR="${HOME}/.claude/recovery"
        if [ -d "$RECOVERY_DIR" ]; then
            LATEST=$(ls -t "$RECOVERY_DIR"/pre-compact-*.md 2>/dev/null | head -1)
            if [ -n "$LATEST" ]; then
                AGE=$(( $(date +%s) - $(stat -c %Y "$LATEST" 2>/dev/null || echo 0) ))
                if [ "$AGE" -lt 7200 ]; then
                    echo "📸 Recent compaction recovery snapshot found ($(( AGE / 60 ))m ago)" >&2
                    echo "  Path: $LATEST" >&2
                fi
            fi
        fi
        ;;

    session_end|Stop)
        # Save handoff for next session
        cat > "$HANDOFF_FILE" << EOF
# Session Handoff
Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Working directory: $(pwd)
Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'N/A')
Uncommitted: $(git status --porcelain 2>/dev/null | wc -l) files
Last commit: $(git log --oneline -1 2>/dev/null || echo 'N/A')
EOF
        echo "📋 Session handoff saved for next resume" >&2
        ;;
esac

exit 0
