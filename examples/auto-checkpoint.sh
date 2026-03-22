#!/bin/bash
# auto-checkpoint.sh — Auto-commit after every edit for rollback protection
#
# Solves: Context compaction silently reverting uncommitted edits (#34674)
# Also protects against: session crashes, token expiry, any unexpected death
#
# Creates lightweight checkpoint commits after every Edit/Write.
# If anything goes wrong, you can recover with `git log` and `git cherry-pick`.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/auto-checkpoint.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only checkpoint after Edit or Write
[[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]] && exit 0

# Must be in a git repo
git rev-parse --git-dir &>/dev/null || exit 0

# Only commit if there are actual changes
DIRTY=$(git status --porcelain 2>/dev/null | head -1)
[[ -z "$DIRTY" ]] && exit 0

# Create checkpoint commit
git add -A 2>/dev/null
git commit -m "checkpoint: auto-save $(date +%H:%M:%S)" --no-verify 2>/dev/null

exit 0
