#!/bin/bash
# settings-json-model-guard.sh — Backup settings.json before /model changes
#
# Solves: The /model slash command rewrites settings.json completely,
# wiping all hook configurations and custom settings. (#46921)
#
# How it works: PreToolUse(Bash) detects commands that modify
# settings.json (especially from /model). Creates a timestamped
# backup before allowing the write. If hooks are lost after the
# write, the PostToolUse phase restores them.
#
# Usage: Add TWO hooks
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Edit|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/settings-json-model-guard.sh" }]
#     }],
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/settings-json-model-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse+PostToolUse  MATCHER: "Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)

# Only care about settings.json writes
case "$FILE" in
    */.claude/settings.json|*/.claude/settings.local.json) ;;
    *) exit 0 ;;
esac

BACKUP_DIR="$HOME/.claude/settings-backups"
mkdir -p "$BACKUP_DIR"

SETTINGS_FILE="$FILE"
[ ! -f "$SETTINGS_FILE" ] && exit 0

# --- PreToolUse: backup before modification ---
if [[ "$HOOK_EVENT" == "PreToolUse" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BASENAME=$(basename "$SETTINGS_FILE" .json)
    BACKUP="$BACKUP_DIR/${BASENAME}-pre-model-${TIMESTAMP}.json"
    cp "$SETTINGS_FILE" "$BACKUP"

    # Count hooks in current settings
    HOOK_COUNT=$(jq '[.hooks // {} | to_entries[] | .value[] | .hooks // [] | length] | add // 0' "$SETTINGS_FILE" 2>/dev/null || echo 0)
    if [ "$HOOK_COUNT" -gt 0 ]; then
        echo "Settings backup created: $BACKUP ($HOOK_COUNT hooks preserved)" >&2
        # Store hook count for PostToolUse comparison
        echo "$HOOK_COUNT" > "/tmp/cc-settings-hook-count-pre"
    fi
    exit 0
fi

# --- PostToolUse: verify hooks survived ---
if [[ "$HOOK_EVENT" == "PostToolUse" ]]; then
    PRE_COUNT_FILE="/tmp/cc-settings-hook-count-pre"
    [ ! -f "$PRE_COUNT_FILE" ] && exit 0

    PRE_COUNT=$(cat "$PRE_COUNT_FILE" 2>/dev/null || echo 0)
    rm -f "$PRE_COUNT_FILE"

    [ "$PRE_COUNT" -eq 0 ] && exit 0

    # Count hooks after modification
    POST_COUNT=$(jq '[.hooks // {} | to_entries[] | .value[] | .hooks // [] | length] | add // 0' "$SETTINGS_FILE" 2>/dev/null || echo 0)

    if [ "$POST_COUNT" -lt "$PRE_COUNT" ]; then
        LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/settings-pre-model-*.json 2>/dev/null | head -1)
        echo "WARNING: Hook count dropped from $PRE_COUNT to $POST_COUNT after settings modification!" >&2
        echo "  This typically happens when /model rewrites settings.json." >&2
        if [ -n "$LATEST_BACKUP" ]; then
            echo "  Restore hooks: jq -s '.[0] * {hooks: .[1].hooks}' '$SETTINGS_FILE' '$LATEST_BACKUP' > /tmp/merged.json && mv /tmp/merged.json '$SETTINGS_FILE'" >&2
        fi
    fi
    exit 0
fi

exit 0
