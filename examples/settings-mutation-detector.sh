#!/bin/bash
# settings-mutation-detector.sh — Detect unauthorized changes to Claude settings files
#
# Solves: Claude Code can modify its own settings files during
#         a session, potentially disabling safety hooks or
#         changing permissions without user awareness.
#
# How it works: On first run, takes a hash of key settings files.
#   On subsequent runs, compares the current hash. If changed,
#   warns the user. This catches silent permission escalation
#   or hook removal.
#
# TRIGGER: PostToolUse
# MATCHER: ""

set -euo pipefail

HASH_FILE="/tmp/claude-settings-hash-$$"

# Files to monitor
SETTINGS_FILES=""
for f in \
  ".claude/settings.json" \
  ".claude/settings.local.json" \
  "${HOME}/.claude/settings.json" \
  "${HOME}/.claude/settings.local.json"; do
  [ -f "$f" ] && SETTINGS_FILES="$SETTINGS_FILES $f"
done

[ -z "$SETTINGS_FILES" ] && exit 0

# Calculate current hash
CURRENT_HASH=$(cat $SETTINGS_FILES 2>/dev/null | md5sum | cut -d' ' -f1)

if [ -f "$HASH_FILE" ]; then
  PREV_HASH=$(cat "$HASH_FILE")
  if [ "$CURRENT_HASH" != "$PREV_HASH" ]; then
    echo "WARNING: Claude settings files were modified during this session!" >&2
    echo "  Files monitored: $SETTINGS_FILES" >&2
    echo "  Review changes to ensure hooks and permissions are intact." >&2
  fi
fi

echo "$CURRENT_HASH" > "$HASH_FILE"
exit 0
