#!/bin/bash
# ================================================================
# reinject-claudemd.sh — Re-inject CLAUDE.md content after compact
# ================================================================
# PURPOSE:
#   After /compact, Claude Code often "forgets" CLAUDE.md rules.
#   This SessionStart hook reads CLAUDE.md and outputs its content
#   as a reminder, ensuring rules persist across sessions.
#
#   GitHub #6354 (27r) — "Claude forgets everything in CLAUDE.md
#   after compaction"
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# HOW IT WORKS:
#   On session start, reads CLAUDE.md from the current project
#   and outputs key rules as a reminder message.
# ================================================================

# Look for CLAUDE.md in current directory and parents
CLAUDE_MD=""
DIR="$(pwd)"
while [ "$DIR" != "/" ]; do
    if [ -f "$DIR/CLAUDE.md" ]; then
        CLAUDE_MD="$DIR/CLAUDE.md"
        break
    fi
    DIR=$(dirname "$DIR")
done

if [ -z "$CLAUDE_MD" ]; then
    exit 0
fi

# Read CLAUDE.md and extract key rules (lines starting with - or *)
RULES=$(grep -E '^\s*[-*]' "$CLAUDE_MD" 2>/dev/null | head -20)

if [ -n "$RULES" ]; then
    echo "REMINDER: CLAUDE.md rules (from $CLAUDE_MD):" >&2
    echo "$RULES" >&2
fi

exit 0
