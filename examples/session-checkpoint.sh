#!/bin/bash
# session-checkpoint.sh — Auto-save session state on every stop
#
# Solves: Session crashes/disconnects causing expensive re-analysis
# of the entire codebase on next start (#37866)
#
# Saves: git state, recent commits, modified files, working directory.
# Next session reads the checkpoint instead of re-analyzing everything.
#
# Usage: Add to settings.json as a Stop hook
#
# {
#   "hooks": {
#     "Stop": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-checkpoint.sh" }]
#     }]
#   }
# }
#
# Recovery: Add to CLAUDE.md:
#   "If ~/.claude/checkpoints/ has a file for this project, read it first."
#
# TRIGGER: Stop  MATCHER: ""

INPUT=$(cat)
REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty' 2>/dev/null)

CHECKPOINT_DIR="$HOME/.claude/checkpoints"
mkdir -p "$CHECKPOINT_DIR"

PROJECT_NAME=$(basename "$(pwd)")
CHECKPOINT="$CHECKPOINT_DIR/${PROJECT_NAME}-latest.md"

{
    echo "# Session Checkpoint"
    echo "Saved: $(date -Iseconds)"
    echo "Directory: $(pwd)"
    echo "Stop reason: ${REASON:-unknown}"
    echo ""
    echo "## Recent Commits"
    git log --oneline -10 2>/dev/null || echo "(not a git repo)"
    echo ""
    echo "## Uncommitted Changes"
    git diff --stat 2>/dev/null || echo "(none)"
    echo ""
    echo "## Staged Files"
    git diff --cached --name-only 2>/dev/null || echo "(none)"
    echo ""
    echo "## Current Branch"
    git branch --show-current 2>/dev/null || echo "(unknown)"
} > "$CHECKPOINT" 2>/dev/null

# Cleanup: keep only last 10 checkpoints
ls -t "$CHECKPOINT_DIR"/*.md 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null

exit 0
