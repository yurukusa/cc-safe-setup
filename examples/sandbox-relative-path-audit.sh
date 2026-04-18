#!/bin/bash
# sandbox-relative-path-audit.sh — Detect relative paths in sandbox settings that are silently ignored
#
# CRITICAL: denyWrite, denyRead, and allowWrite in settings.json only work
# with ABSOLUTE paths. Relative paths are SILENTLY IGNORED — no error, no
# warning, and zero protection. Users who think they've protected sensitive
# directories may have no actual protection.
#
# Born from: https://github.com/anthropics/claude-code/issues/50454
#
# TRIGGER: PreToolUse  MATCHER: "Bash|Write|Edit"
# Best used as a Notification hook (exit 0 always) to alert without blocking.

INPUT=$(cat)
# Only run once per session (check marker file)
MARKER="/tmp/cc-sandbox-audit-$$"
[ -f "$MARKER" ] && exit 0
touch "$MARKER"

# Find settings.json locations
SETTINGS_FILES=""
[ -f "$HOME/.claude/settings.json" ] && SETTINGS_FILES="$HOME/.claude/settings.json"
[ -f ".claude/settings.json" ] && SETTINGS_FILES="$SETTINGS_FILES .claude/settings.json"
[ -f "$HOME/.claude/settings.local.json" ] && SETTINGS_FILES="$SETTINGS_FILES $HOME/.claude/settings.local.json"

[ -z "$SETTINGS_FILES" ] && exit 0

FOUND_RELATIVE=0
for SFILE in $SETTINGS_FILES; do
    for KEY in denyWrite denyRead allowWrite; do
        PATHS=$(jq -r ".permissions.${KEY}[]? // empty" "$SFILE" 2>/dev/null)
        [ -z "$PATHS" ] && continue
        while IFS= read -r P; do
            [ -z "$P" ] && continue
            if [[ "$P" != /* ]] && [[ "$P" != "~"* ]]; then
                echo "⚠ SANDBOX WARNING: Relative path in ${KEY} is SILENTLY IGNORED" >&2
                echo "  File: $SFILE" >&2
                echo "  Path: \"$P\" → has NO effect" >&2
                echo "  Fix:  Use absolute path: \"$(realpath -m "$P" 2>/dev/null || echo "$PWD/$P")\"" >&2
                FOUND_RELATIVE=1
            fi
        done <<< "$PATHS"
    done
done

if [ "$FOUND_RELATIVE" -eq 1 ]; then
    echo "" >&2
    echo "See: https://github.com/anthropics/claude-code/issues/50454" >&2
fi

exit 0
