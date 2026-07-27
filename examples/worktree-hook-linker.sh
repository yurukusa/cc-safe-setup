#!/bin/bash
# worktree-hook-linker.sh — Auto-link settings to worktrees
#
# Solves: In git worktrees, .claude/settings.json is not found because
# worktrees share .git but not the working directory. All hooks
# become silently disabled. (#46808)
#
# How it works: On SessionStart, checks if the current directory is a
# git worktree. If so, creates a symlink from the worktree's
# .claude/settings.json to the main tree's settings. This ensures
# hooks work identically in worktrees.
#
# {
#   "hooks": {
#     "Notification": [{
#       "matcher": "SessionStart",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/worktree-hook-linker.sh" }]
#     }]
#   }
# }
#
# TRIGGER: Notification
# MATCHER: "SessionStart"

# Detect if we're in a git worktree
GITDIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
echo "$GITDIR" | grep -q "worktrees" || exit 0

# We're in a worktree — find the main working tree
MAIN_GITDIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
MAIN_WORKDIR=$(echo "$MAIN_GITDIR" | sed 's|/.git$||')

MAIN_CLAUDE_DIR="$MAIN_WORKDIR/.claude"
LOCAL_CLAUDE_DIR=".claude"

# Skip if main tree has no .claude directory
[ -d "$MAIN_CLAUDE_DIR" ] || exit 0

# Create .claude directory in worktree if needed
mkdir -p "$LOCAL_CLAUDE_DIR" 2>/dev/null

# Link settings files if they exist in main but not in worktree
for f in settings.json settings.local.json; do
    MAIN_FILE="$MAIN_CLAUDE_DIR/$f"
    LOCAL_FILE="$LOCAL_CLAUDE_DIR/$f"

    [ ! -f "$MAIN_FILE" ] && continue

    if [ ! -e "$LOCAL_FILE" ]; then
        ln -s "$MAIN_FILE" "$LOCAL_FILE"
        echo "Linked $f from main tree → worktree (hooks now active)" >&2
    elif [ -L "$LOCAL_FILE" ]; then
        # Already a symlink — verify it points to the right place
        TARGET=$(readlink -f "$LOCAL_FILE" 2>/dev/null)
        EXPECTED=$(readlink -f "$MAIN_FILE" 2>/dev/null)
        if [ "$TARGET" != "$EXPECTED" ]; then
            rm "$LOCAL_FILE"
            ln -s "$MAIN_FILE" "$LOCAL_FILE"
            echo "Re-linked $f (was pointing to wrong location)" >&2
        fi
    fi
done

# Also link hooks directory if it exists
MAIN_HOOKS="$MAIN_CLAUDE_DIR/hooks"
LOCAL_HOOKS="$LOCAL_CLAUDE_DIR/hooks"
if [ -d "$MAIN_HOOKS" ] && [ ! -e "$LOCAL_HOOKS" ]; then
    ln -s "$MAIN_HOOKS" "$LOCAL_HOOKS"
    echo "Linked hooks/ directory from main tree → worktree" >&2
fi

exit 0
