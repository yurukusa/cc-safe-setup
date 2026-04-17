#!/bin/bash
# settings-integrity-monitor.sh — Detect unexpected settings.json changes
# Trigger: PreToolUse
# Matcher: (empty — runs on every tool use)
#
# The /model command silently rewrites settings.json from scratch,
# removing sandbox restrictions and hook configurations.
# See: https://github.com/anthropics/claude-code/issues/44791
#
# This hook maintains a checksum of settings.json and warns when
# it changes outside your control. It also creates automatic backups
# so you can restore your configuration.
#
# TRIGGER: PreToolUse  MATCHER: ""

SETTINGS="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
BACKUP_DIR="$HOME/.claude/settings-backups"
CHECKSUM_FILE="$BACKUP_DIR/.checksum"

# Exit silently if settings.json doesn't exist
[ -f "$SETTINGS" ] || exit 0

mkdir -p "$BACKUP_DIR"

CURRENT_HASH=$(sha256sum "$SETTINGS" 2>/dev/null | cut -d' ' -f1)

if [ ! -f "$CHECKSUM_FILE" ]; then
    # First run: save baseline
    echo "$CURRENT_HASH" > "$CHECKSUM_FILE"
    cp "$SETTINGS" "$BACKUP_DIR/settings.json.baseline"
    exit 0
fi

SAVED_HASH=$(cat "$CHECKSUM_FILE" 2>/dev/null)

if [ "$CURRENT_HASH" != "$SAVED_HASH" ]; then
    # Settings changed — create timestamped backup of PREVIOUS version
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    if [ -f "$BACKUP_DIR/settings.json.latest" ]; then
        cp "$BACKUP_DIR/settings.json.latest" "$BACKUP_DIR/settings.json.$TIMESTAMP"
    fi
    # Save current as latest
    cp "$SETTINGS" "$BACKUP_DIR/settings.json.latest"
    echo "$CURRENT_HASH" > "$CHECKSUM_FILE"

    # Count hooks in old vs new
    OLD_HOOKS=$(jq '[.hooks | to_entries[].value[].hooks[]?] | length' "$BACKUP_DIR/settings.json.$TIMESTAMP" 2>/dev/null || echo "?")
    NEW_HOOKS=$(jq '[.hooks | to_entries[].value[].hooks[]?] | length' "$SETTINGS" 2>/dev/null || echo "?")

    echo "⚠ settings.json was modified (hooks: $OLD_HOOKS → $NEW_HOOKS)" >&2
    echo "  Backup saved: $BACKUP_DIR/settings.json.$TIMESTAMP" >&2
    echo "  Restore: cp $BACKUP_DIR/settings.json.$TIMESTAMP $SETTINGS" >&2
fi

exit 0
