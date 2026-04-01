#!/bin/bash
# ================================================================
# pre-compact-transcript-backup.sh — Backup transcript before compaction
# ================================================================
# PURPOSE:
#   Creates a full copy of the session transcript JSONL before
#   compaction begins. If compaction fails (rate limit, API error),
#   the original transcript is preserved and can be restored.
#
# TRIGGER: PreCompact
# MATCHER: (none — PreCompact has no matcher)
#
# WHY THIS MATTERS:
#   Compaction wipes message content from the JSONL transcript
#   BEFORE the compaction API call succeeds. If the API call
#   fails (e.g., rate limit), all original content is permanently
#   lost — the transcript is left with thousands of empty messages
#   and no compaction summary. This hook ensures a recoverable
#   backup exists.
#
# WHAT IT DOES:
#   1. Reads transcript_path from stdin JSON
#   2. Copies the full JSONL file to a backup location
#   3. Keeps last 3 backups per session to save disk space
#
# CONFIGURATION:
#   CC_COMPACT_BACKUP_DIR — backup directory
#     (default: ~/.claude/compact-backups)
#   CC_COMPACT_BACKUP_KEEP — number of backups to keep (default: 3)
#
# RECOVERY:
#   cp ~/.claude/compact-backups/<session-id>/latest.jsonl \
#      ~/.claude/projects/<project>/sessions/<session>.jsonl
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/40352
# ================================================================

set -u

INPUT=$(cat)

BACKUP_DIR="${CC_COMPACT_BACKUP_DIR:-${HOME}/.claude/compact-backups}"
KEEP="${CC_COMPACT_BACKUP_KEEP:-3}"

# Get transcript path from hook input
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
fi

# Create backup
BASENAME=$(basename "$TRANSCRIPT" .jsonl)
DEST_DIR="${BACKUP_DIR}/${BASENAME}"
mkdir -p "$DEST_DIR"

TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
BACKUP_FILE="${DEST_DIR}/${TIMESTAMP}.jsonl"

cp "$TRANSCRIPT" "$BACKUP_FILE" 2>/dev/null

if [ -f "$BACKUP_FILE" ]; then
    SIZE=$(du -sh "$BACKUP_FILE" 2>/dev/null | cut -f1)
    printf 'Pre-compact backup: %s (%s)\n' "$BACKUP_FILE" "$SIZE" >&2

    # Prune old backups
    ls -1t "$DEST_DIR"/*.jsonl 2>/dev/null | tail -n +$((KEEP + 1)) | xargs rm -f 2>/dev/null
fi

exit 0
