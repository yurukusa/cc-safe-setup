#!/bin/bash
# ================================================================
# session-backup-on-start.sh — Backup session JSONL files on start
# ================================================================
# PURPOSE:
#   Creates a timestamped backup of all session JSONL files when
#   a new session starts. Protects against silent deletion of
#   session data by the desktop app or unexpected corruption.
#
# TRIGGER: SessionStart
# MATCHER: (none — SessionStart has no matcher)
#
# WHY THIS MATTERS:
#   The Claude Code desktop app has been observed silently deleting
#   session JSONL files while leaving subagent directories intact.
#   Without backups, entire conversation histories are lost with
#   no way to recover them.
#
# WHAT IT DOES:
#   1. Finds the project session directory
#   2. Copies all .jsonl files to a timestamped backup directory
#   3. Keeps only the last 5 backups to avoid disk bloat
#
# CONFIGURATION:
#   CC_SESSION_BACKUP_DIR — backup location (default: ~/.claude/session-backups)
#   CC_SESSION_BACKUP_KEEP — number of backups to keep (default: 5)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41874
# ================================================================

set -u

BACKUP_DIR="${CC_SESSION_BACKUP_DIR:-${HOME}/.claude/session-backups}"
KEEP="${CC_SESSION_BACKUP_KEEP:-5}"

# Find the current project's session directory
CWD=$(pwd)
PROJECT_NAME=$(printf '%s' "$CWD" | sed 's|/|-|g; s|^-||')
SESSION_DIR="${HOME}/.claude/projects/${PROJECT_NAME}"

if [ ! -d "$SESSION_DIR" ]; then
    exit 0
fi

# Check if there are JSONL files to back up
JSONL_COUNT=$(find "$SESSION_DIR" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null | wc -l)
if [ "$JSONL_COUNT" -eq 0 ]; then
    exit 0
fi

# Create timestamped backup
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
DEST="${BACKUP_DIR}/${PROJECT_NAME}/${TIMESTAMP}"
mkdir -p "$DEST"

# Copy JSONL files (not subdirectories — those are subagent sessions)
cp "$SESSION_DIR"/*.jsonl "$DEST/" 2>/dev/null

BACKED_UP=$(find "$DEST" -name "*.jsonl" -type f 2>/dev/null | wc -l)

# Prune old backups (keep last N)
PARENT="${BACKUP_DIR}/${PROJECT_NAME}"
if [ -d "$PARENT" ]; then
    ls -1dt "$PARENT"/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | xargs rm -rf 2>/dev/null
fi

if [ "$BACKED_UP" -gt 0 ]; then
    printf 'Session backup: %d JSONL files saved to %s\n' "$BACKED_UP" "$DEST" >&2
fi

exit 0
