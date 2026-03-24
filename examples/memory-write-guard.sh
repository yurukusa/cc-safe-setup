#!/bin/bash
# ================================================================
# memory-write-guard.sh — Log writes to ~/.claude/ directory
# ================================================================
# PURPOSE:
#   Claude auto-writes to ~/.claude/projects/*/memory/ without
#   user visibility. This hook logs all writes to ~/.claude/ paths
#   so users know what's being stored.
#
# TRIGGER: PreToolUse  MATCHER: "Write|Edit"
#
# Born from: https://github.com/anthropics/claude-code/issues/38040
#   "No way to enforce approval on all file modifications"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Check if targeting ~/.claude/
case "$FILE" in
    */.claude/*|~/.claude/*)
        # Log the write
        LOG="$HOME/.claude/memory-writes.log"
        echo "[$(date -Iseconds)] Write to: $FILE" >> "$LOG" 2>/dev/null

        # Only warn (don't block) — memory writes are usually intentional
        echo "NOTE: Writing to Claude config directory: $FILE" >&2

        # Block writes to settings.json unless explicitly allowed
        case "$FILE" in
            */settings.json|*/settings.local.json)
                echo "WARNING: Modifying Claude Code settings file." >&2
                echo "Verify this change is intentional." >&2
                ;;
        esac
        ;;
esac

exit 0
