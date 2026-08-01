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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-edit-counter-test-gate-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [edit-counter-test-gate]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
