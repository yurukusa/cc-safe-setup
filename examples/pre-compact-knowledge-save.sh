#!/bin/bash
# pre-compact-knowledge-save.sh — Save critical context before compaction
#
# Solves: Context compaction losing important decisions, file locations,
#         and progress state. After /compact, Claude forgets what it was
#         doing and repeats work or contradicts earlier decisions.
#
# How it works: PreCompact hook that saves the current session state
#   to a checkpoint file that survives compaction. The model can read
#   this file after compaction to restore context.
#
# The checkpoint includes: current task, recent decisions, modified files.
#
# TRIGGER: PreCompact
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)

CHECKPOINT="${CC_COMPACT_CHECKPOINT:-.claude/pre-compact-checkpoint.md}"
mkdir -p "$(dirname "$CHECKPOINT")"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Gather session state
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
MODIFIED=$(git diff --name-only 2>/dev/null | head -10 || echo "none")
STAGED=$(git diff --cached --name-only 2>/dev/null | head -10 || echo "none")
RECENT_COMMITS=$(git log --oneline -3 2>/dev/null || echo "none")

cat > "$CHECKPOINT" << CHECKPOINT_EOF
# Pre-Compact Checkpoint
Generated: ${TIMESTAMP}
Branch: ${GIT_BRANCH}

## Modified files (not staged)
${MODIFIED}

## Staged files
${STAGED}

## Recent commits
${RECENT_COMMITS}

## Notes
Read this file after compaction to restore context.
Check tasks/todo.md for current task progress.
CHECKPOINT_EOF

echo "Pre-compact checkpoint saved to $CHECKPOINT" >&2

exit 0
