#!/bin/bash
# pre-compact-checkpoint.sh — Auto-save before context compaction
#
# Uses the PreCompact hook event to create a git checkpoint before
# Claude Code compresses the conversation context. This ensures
# uncommitted edits are preserved even if compaction loses track
# of recent changes.
#
# Solves: Context compaction can cause Claude to lose awareness of
#         recent file edits (#34674). A pre-compaction checkpoint
#         makes recovery trivial: just run `git log --oneline -5`.
#
# TRIGGER: PreCompact (fires right before context compression)
# MATCHER: No matcher support — always fires
#
# DECISION CONTROL: None (notification only)
#
# Compared to auto-compact-prep.sh (which uses tool call counting
# on PreToolUse), this hook fires at the exact right moment —
# when compaction actually happens, not on an estimated threshold.

# Check if we're in a git repo
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# Check for uncommitted changes
CHANGES=$(git status --porcelain 2>/dev/null | wc -l)
[ "$CHANGES" -eq 0 ] && exit 0

# Create checkpoint commit
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
TIMESTAMP=$(date -u '+%Y%m%d-%H%M%S')

git add -A 2>/dev/null
git commit -m "checkpoint: pre-compact auto-save (${CHANGES} files, ${TIMESTAMP})" --no-verify 2>/dev/null

echo "📸 Pre-compact checkpoint: ${CHANGES} file(s) saved on ${BRANCH}" >&2
echo "  Recover with: git log --oneline -5" >&2

exit 0
