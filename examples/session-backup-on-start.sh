#!/bin/bash
# ================================================================
# session-backup-on-start.sh — Backup session JSONL files on start
# ================================================================
# PURPOSE:
#   Creates a timestamped backup of all session JSONL files when
#   a new session starts. Protects against silent deletion of
#   session data by the desktop app, the retention cleanup, or
#   unexpected corruption.
#
# TRIGGER: SessionStart
# MATCHER: (none — SessionStart has no matcher)
#
# WHY THIS MATTERS:
#   The Claude Code desktop app has been observed silently deleting
#   session JSONL files while leaving subagent directories intact
#   (#41874). A separate retention cleanup process fires ~12 minutes
#   after session start, sometimes deletes transcripts older than
#   the documented 30-day default, and leaves orphan subagent
#   directories behind when the parent .jsonl is removed (#59248).
#   Both routes destroy operator working history.
#
#   This hook runs at SessionStart, BEFORE either deletion path can
#   fire, so the snapshot captures the pre-cleanup state. Recovery
#   is `cat ~/.claude/session-backups/<project>/<timestamp>/<sid>.jsonl
#   | jq` — the JSONL format is re-parsable without the resume picker.
#
# WHAT IT DOES:
#   1. Finds the project session directory
#   2. Copies all .jsonl files to a timestamped backup directory
#   3. Optionally backs up subagent directories (opt-in for disk reasons)
#   4. Keeps only the last 5 backups to avoid disk bloat
#
# CONFIGURATION:
#   CC_SESSION_BACKUP_DIR        — backup location (default: ~/.claude/session-backups)
#   CC_SESSION_BACKUP_KEEP       — number of backups to keep (default: 5)
#   CC_SESSION_BACKUP_SUBAGENTS  — set to 1 to also copy subagent
#                                  directories. Off by default since
#                                  subagent transcripts can be large.
#                                  Turn on if #59248-style orphan
#                                  subagent directories are a concern.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41874
#   https://github.com/anthropics/claude-code/issues/59248
# ================================================================

set -u

BACKUP_DIR="${CC_SESSION_BACKUP_DIR:-${HOME}/.claude/session-backups}"
KEEP="${CC_SESSION_BACKUP_KEEP:-5}"
INCLUDE_SUBAGENTS="${CC_SESSION_BACKUP_SUBAGENTS:-0}"

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

# Copy JSONL files (top-level parent transcripts)
cp "$SESSION_DIR"/*.jsonl "$DEST/" 2>/dev/null

# Optionally include subagent directories (#59248 orphan-subagent defense)
SUBAGENT_COUNT=0
if [ "$INCLUDE_SUBAGENTS" = "1" ]; then
    for d in "$SESSION_DIR"/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        cp -r "$d" "$DEST/$name" 2>/dev/null && SUBAGENT_COUNT=$((SUBAGENT_COUNT + 1))
    done
fi

BACKED_UP=$(find "$DEST" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null | wc -l)

# Prune old backups (keep last N)
PARENT="${BACKUP_DIR}/${PROJECT_NAME}"
if [ -d "$PARENT" ]; then
    ls -1dt "$PARENT"/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | xargs rm -rf 2>/dev/null
fi

if [ "$BACKED_UP" -gt 0 ]; then
    if [ "$SUBAGENT_COUNT" -gt 0 ]; then
        printf 'Session backup: %d JSONL files + %d subagent dirs saved to %s\n' \
            "$BACKED_UP" "$SUBAGENT_COUNT" "$DEST" >&2
    else
        printf 'Session backup: %d JSONL files saved to %s\n' "$BACKED_UP" "$DEST" >&2
    fi
fi

exit 0
