#!/bin/bash
# ================================================================
# settings-auto-backup.sh — Auto-backup settings on session start
# ================================================================
# PURPOSE:
#   Claude Code auto-updates have been observed silently wiping
#   settings.json, settings.local.json, and plugin state. (#40714)
#   This hook creates rolling backups on every session start and
#   warns if settings appear to have been reset.
#
# TRIGGER: Notification
# MATCHER: "SessionStart"
#
# BACKUPS: ~/.claude/settings-backups/
# ================================================================

BACKUP_DIR="$HOME/.claude/settings-backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKED_UP=0

# Backup settings files
for f in settings.json settings.local.json; do
    SRC="$HOME/.claude/$f"
    if [ -f "$SRC" ] && [ -s "$SRC" ]; then
        cp "$SRC" "$BACKUP_DIR/${f%.json}-${TIMESTAMP}.json"
        BACKED_UP=$((BACKED_UP + 1))
    fi
done

# Keep only last 10 backups per file type
for prefix in settings settings.local; do
    ls -t "$BACKUP_DIR/${prefix}-"*.json 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
done

# Detect suspicious settings reset
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    KEY_COUNT=$(jq 'keys | length' "$SETTINGS" 2>/dev/null || echo 0)
    if [ "$KEY_COUNT" -le 1 ]; then
        LATEST_BACKUP=$(ls -t "$BACKUP_DIR/settings-"*.json 2>/dev/null | head -2 | tail -1)
        if [ -n "$LATEST_BACKUP" ]; then
            BACKUP_KEYS=$(jq 'keys | length' "$LATEST_BACKUP" 2>/dev/null || echo 0)
            if [ "$BACKUP_KEYS" -gt "$KEY_COUNT" ]; then
                echo "⚠ Settings may have been reset ($KEY_COUNT keys vs $BACKUP_KEYS in backup)" >&2
                echo "  Restore: cp '$LATEST_BACKUP' '$SETTINGS'" >&2
            fi
        fi
    fi
fi

exit 0
