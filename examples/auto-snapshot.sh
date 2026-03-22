#!/bin/bash
# auto-snapshot.sh — Automatic file snapshots before every edit
#
# Solves: Claude reverting verified changes after encountering
#         contradictory information (sycophantic capitulation)
#         (#37386, #37457)
#
# How it works:
#   - Runs as a PreToolUse hook on Edit/Write
#   - Copies the file to ~/.claude/snapshots/ before modification
#   - When Claude walks back correct work, diff the snapshot
#     against the current file and restore
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/auto-snapshot.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only snapshot Edit and Write operations
if [[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]]; then
    exit 0
fi

# Only snapshot existing files (Write to new files has nothing to save)
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    exit 0
fi

SNAP_DIR="$HOME/.claude/snapshots/$(date +%Y%m%d)"
mkdir -p "$SNAP_DIR" 2>/dev/null

# Use filename + timestamp to avoid collisions
BASENAME=$(basename "$FILE")
TIMESTAMP=$(date +%H%M%S)
cp "$FILE" "$SNAP_DIR/${BASENAME}.${TIMESTAMP}" 2>/dev/null

# Keep snapshots manageable — delete files older than 7 days
find "$HOME/.claude/snapshots" -type f -mtime +7 -delete 2>/dev/null
find "$HOME/.claude/snapshots" -type d -empty -delete 2>/dev/null

exit 0
