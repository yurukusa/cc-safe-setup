#!/bin/bash
# file-edit-backup.sh — Auto-backup files before Edit/Write overwrites them
#
# Solves: Claude Code overwrites important files and the changes are hard
#         to reverse. This creates a timestamped backup before each edit,
#         so you can always recover the previous version.
#
# Real incidents:
#   #37478 — .bashrc overwritten without permission
#   #32938 — 11h of inference output deleted
#   #36339 — C:\Users directory wiped (NTFS junction traversal)
#
# Backups go to ~/.claude/file-backups/ with timestamps.
# Old backups (>7 days) are auto-cleaned to prevent disk bloat.
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0  # New file, nothing to backup

BACKUP_DIR="$HOME/.claude/file-backups"
mkdir -p "$BACKUP_DIR"

# Create backup with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SAFE_NAME=$(echo "$FILE" | tr '/' '_' | sed 's/^_//')
BACKUP_PATH="${BACKUP_DIR}/${SAFE_NAME}.${TIMESTAMP}"

cp "$FILE" "$BACKUP_PATH" 2>/dev/null

# Clean old backups (>7 days)
find "$BACKUP_DIR" -type f -mtime +7 -delete 2>/dev/null

exit 0
