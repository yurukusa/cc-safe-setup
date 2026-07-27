#!/bin/bash
# edit-counter-test-gate.sh — Require testing after N consecutive edits
#
# Solves: Reactive cycling through fixes without testing (#40401).
#         Opus writing 4 different fix approaches in sequence without
#         verifying any of them actually work.
#
# How it works: PostToolUse hook on Edit that counts consecutive edits.
#   After CC_MAX_EDITS_BEFORE_TEST (default 3) edits without a Bash
#   command (assumed test/build), warns the model to test first.
#
# TRIGGER: PostToolUse
# MATCHER: "Edit|Bash"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
MAX_EDITS="${CC_MAX_EDITS_BEFORE_TEST:-3}"
COUNTER_FILE="/tmp/claude-edit-test-gate-${PPID:-0}"

case "$TOOL" in
  Edit|Write)
    # Increment edit counter
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNTER_FILE"

    if [ "$COUNT" -ge "$MAX_EDITS" ]; then
      echo "WARNING: $COUNT consecutive edits without testing." >&2
      echo "" >&2
      echo "Run your test/build command before making more changes." >&2
      echo "Untested fixes compound — verify each approach works" >&2
      echo "before trying the next one." >&2
      # Warning only — change to exit 2 to block
    fi
    ;;
  Bash)
    # Bash command (likely test/build) — reset counter
    echo "0" > "$COUNTER_FILE"
    ;;
esac

exit 0
