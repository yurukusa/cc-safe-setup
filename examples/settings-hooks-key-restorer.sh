#!/bin/bash
# settings-hooks-key-restorer.sh — Detect silent loss of top-level `hooks` key in settings.json
# Trigger: SessionStart
# Matcher: (none — runs on every session start)
#
# Issue #59870 — when the user accepts a new permission, Claude Code rewrites
# `~/.claude/settings.json` and silently drops the top-level `hooks` key.
# Other top-level keys (`permissions`, `model`, etc.) are preserved.
# Tools that register PreToolUse/PostToolUse/Stop hooks via settings.json
# then "stop working" mid-session with no warning.
#
# This hook runs at SessionStart, compares the current settings.json against
# the most recent backup, and warns if the `hooks` key has disappeared.
# The hook does NOT auto-restore; auto-restoration risks reintroducing
# stale or wrong hooks. Instead it prints the restoration command for
# the user to verify and apply.
#
# Companion to settings-integrity-monitor.sh (which tracks hash-level changes
# but does not specialize on the hooks-key disappearance pattern).
#
# TRIGGER: SessionStart  MATCHER: ""

SETTINGS="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
BACKUP_DIR="$HOME/.claude/settings-backups"

# Exit silently if settings.json doesn't exist
[ -f "$SETTINGS" ] || exit 0

# Exit silently if no backups exist yet
[ -d "$BACKUP_DIR" ] || exit 0

# Exit silently if settings.json is malformed (a separate hook handles that)
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
    exit 0
fi

# Check current settings.json has hooks key
CURRENT_HAS_HOOKS=$(jq 'has("hooks")' "$SETTINGS" 2>/dev/null || echo "false")

# If current still has hooks, nothing to do
if [ "$CURRENT_HAS_HOOKS" = "true" ]; then
    CURRENT_HOOK_COUNT=$(jq '[.hooks | to_entries[].value[].hooks[]?] | length' "$SETTINGS" 2>/dev/null || echo "0")
    # Even if hooks key is present, warn if count is 0 (the key exists but has been emptied)
    if [ "$CURRENT_HOOK_COUNT" = "0" ]; then
        echo "⚠ settings.json has 'hooks' key but it is empty. If you registered hooks via settings.json, they may have been silently removed." >&2
        echo "  See https://github.com/anthropics/claude-code/issues/59870 for the silent-drop pattern." >&2
    fi
    exit 0
fi

# Current does NOT have hooks key. Look at backups for the most recent one with hooks.
LATEST_BACKUP=""
if [ -f "$BACKUP_DIR/settings.json.latest" ]; then
    LATEST_HAS_HOOKS=$(jq 'has("hooks")' "$BACKUP_DIR/settings.json.latest" 2>/dev/null || echo "false")
    if [ "$LATEST_HAS_HOOKS" = "true" ]; then
        LATEST_BACKUP="$BACKUP_DIR/settings.json.latest"
    fi
fi

if [ -z "$LATEST_BACKUP" ] && [ -f "$BACKUP_DIR/settings.json.baseline" ]; then
    BASELINE_HAS_HOOKS=$(jq 'has("hooks")' "$BACKUP_DIR/settings.json.baseline" 2>/dev/null || echo "false")
    if [ "$BASELINE_HAS_HOOKS" = "true" ]; then
        LATEST_BACKUP="$BACKUP_DIR/settings.json.baseline"
    fi
fi

# If no backup with hooks exists, the user never had hooks in settings.json. Exit silently.
if [ -z "$LATEST_BACKUP" ]; then
    exit 0
fi

# Hooks were present in a prior backup but are now gone. Warn and suggest restoration.
PRIOR_HOOK_COUNT=$(jq '[.hooks | to_entries[].value[].hooks[]?] | length' "$LATEST_BACKUP" 2>/dev/null || echo "?")

cat >&2 <<EOF
⚠ SILENT HOOKS LOSS DETECTED

settings.json no longer contains the top-level 'hooks' key, but the most
recent backup ($LATEST_BACKUP) had $PRIOR_HOOK_COUNT hook entries.

This matches issue #59870: when Claude Code rewrites settings.json after a
permission grant, it silently drops the top-level 'hooks' key. Other keys
(permissions, model, etc.) are preserved.

To restore the hooks key from the backup, run:

  jq -s '.[0] + {hooks: .[1].hooks}' "$SETTINGS" "$LATEST_BACKUP" > /tmp/settings-restored.json && \\
    mv /tmp/settings-restored.json "$SETTINGS"

Then verify with:

  jq '.hooks | keys' "$SETTINGS"

If the restored hooks are stale, edit the backup file before running the merge.
This hook does NOT auto-restore to avoid reintroducing wrong hooks.

EOF

exit 0
