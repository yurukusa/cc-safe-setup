#!/bin/bash
# file-change-monitor.sh — Track all files modified during a session
#
# Solves: No visibility into which files Claude changed during a session.
#         After long autonomous runs, you can't easily audit what was touched.
#
# How it works: After every Edit/Write, logs the file path and timestamp
#   to ~/.claude/session-changes.log. Review at session end or anytime.
#
# Log format: ISO timestamp | tool | file path
# Example: 2026-03-28T09:15:00 | Edit | /home/user/project/src/main.ts
#
# Clear log at session start by adding a SessionStart hook,
# or keep it as a running audit trail.
#
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only track Edit and Write
[[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]] && exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0

LOG="$HOME/.claude/session-changes.log"
TIMESTAMP=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

echo "$TIMESTAMP | $TOOL | $FILE" >> "$LOG"

exit 0
