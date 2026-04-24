#!/bin/bash
# model-version-lock.sh — silent mid-session downgrade detector (Incident 4)
# Why: Opus 4.7 sessions sometimes migrate mid-session to a different model
#      (for example the 1M-context automatic switch, #49541) with no client-
#      visible announcement. The downgrade silently changes token accounting,
#      context window, and quality. This hook writes a lock file containing
#      the model id seen on the first turn of the session and emits a stderr
#      banner whenever a later turn reports a different model id.
# Event: PostToolUse  MATCHER: "*"
# Action: First per-session call creates
#         ~/.claude/logs/model-locks/<session-id>.model. Subsequent calls read
#         the lock and compare. Mismatch → banner. /model is the expected
#         user path for intentional switches, so the banner says so.
#
# To reset: rm -rf ~/.claude/logs/model-locks/   (between sessions that
# deliberately switch models, otherwise locks accumulate)

set -u

LOG_DIR="${HOME}/.claude/logs"
LOCK_DIR="${LOG_DIR}/model-locks"
mkdir -p "$LOCK_DIR" 2>/dev/null

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
[ "$SESSION_ID" = "unknown" ] && exit 0

# Resolve the current model. PostToolUse payload rarely has it directly, so
# read the last assistant turn from the transcript for its "model" field.
MODEL=""
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  MODEL=$(tac "$TRANSCRIPT" 2>/dev/null \
          | grep -m1 '"model"' \
          | jq -r '.message.model // .model // empty' 2>/dev/null)
fi

# Fallback: environment variable (used by some wrappers and tests).
if [ -z "$MODEL" ] && [ -n "${CLAUDE_MODEL:-}" ]; then
  MODEL="$CLAUDE_MODEL"
fi

# If we still do not know the model, do nothing — no false positives.
[ -z "$MODEL" ] && exit 0

LOCK_FILE="${LOCK_DIR}/${SESSION_ID}.model"

if [ ! -s "$LOCK_FILE" ]; then
  printf '%s\n' "$MODEL" > "$LOCK_FILE"
  exit 0
fi

LOCKED=$(cat "$LOCK_FILE" 2>/dev/null)
if [ -n "$LOCKED" ] && [ "$LOCKED" != "$MODEL" ]; then
  echo "⚠ model-version-lock: $LOCKED → $MODEL (session $SESSION_ID)" >&2
  echo "  Use /model to switch intentionally. Silent migrations (#49541) change token accounting and quality." >&2
  # Update the lock so we do not emit again for the same transition this
  # session. Users who want to see every transition can remove this line.
  printf '%s\n' "$MODEL" > "$LOCK_FILE"
fi

exit 0
