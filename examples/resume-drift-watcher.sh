#!/bin/bash
# resume-drift-watcher.sh — resume attachment relocation detector (Incident 2)
# Why: v2.1.69–v2.1.89 had a bug where --resume would relocate the original
#      attachment payload out of messages[0] and into a later turn. The bug
#      was marked fixed but residual drift still shows a tiny messages[0]
#      (~350 bytes) when a resumed session is working correctly. A session
#      with drifted attachments shows a very small messages[0] followed by
#      disproportionately large messages[N] entries.
# Event: PostToolUse  MATCHER: "*"
# Action: Per turn, record first-message byte length and total-message byte
#         length to ~/.claude/logs/resume-drift.log. Compare manually: a
#         session started with --resume whose messages[0] is much smaller
#         than a fresh session's is a drift candidate.
#
# Review with:
#   awk -F'\t' '$3<500 && $4>50000 {print}' ~/.claude/logs/resume-drift.log

set -u

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/resume-drift.log"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; then
  exit 0
fi

# First message — scan from top; stop at first user message.
FIRST_MSG=$(grep -m1 '"role":"user"' "$TRANSCRIPT" 2>/dev/null || true)
FIRST_LEN=$(printf '%s' "$FIRST_MSG" | wc -c | tr -d ' ')

# Total body size = file size of the transcript itself. This is a conservative
# proxy for request-body size: a resumed session with many large intermediate
# messages will have a large transcript.
TOTAL_LEN=$(wc -c < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
TOTAL_LEN="${TOTAL_LEN:-0}"

TURN_COUNT=$(grep -c '"role":' "$TRANSCRIPT" 2>/dev/null || echo 0)

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\t%s\t%s\t%s\t%s\n' \
  "$TS" "$SESSION_ID" "$FIRST_LEN" "$TOTAL_LEN" "$TURN_COUNT" \
  >> "$LOG_FILE"

# Only emit a stderr warning after turn 2 (per Appendix B: "Only investigate
# after the first two turns of a resumed session"). Threshold: first-user
# message under 500 bytes while total already exceeds 50 KB = drift candidate.
if [ "$TURN_COUNT" -gt 4 ] && [ "$FIRST_LEN" -lt 500 ] && [ "$TOTAL_LEN" -gt 50000 ]; then
  echo "⚠ resume-drift signal: messages[0]=${FIRST_LEN}B / total=${TOTAL_LEN}B (see #43278)" >&2
fi

exit 0
