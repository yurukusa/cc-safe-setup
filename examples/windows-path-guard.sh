#!/bin/bash
# windows-path-guard.sh — Prevent NTFS junction/symlink traversal destruction
#
# Solves: rm -rf following NTFS junctions to delete user directories (#36339).
#         On Windows (WSL/Git Bash), `rm -rf` can traverse NTFS junctions
#         and delete system directories like C:\Users.
#
# How it works: Before rm operations, checks if the target path is
#   a symlink or junction that points outside the project directory.
#   Blocks rm if it would traverse to a system-critical location.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check rm commands
echo "$COMMAND" | grep -qE '^\s*rm\s|;\s*rm\s|&&\s*rm\s' || exit 0

# Extract rm targets (simplified — handles common patterns)
TARGETS=$(echo "$COMMAND" | grep -oE 'rm\s+[^ ;|&]+(\s+[^ ;|&-]+)*' | sed 's/^rm\s*//' | sed 's/-[rfvid]*\s*//g')

for target in $TARGETS; do
    [ -z "$target" ] && continue

    # Resolve the real path
    REAL_PATH=$(readlink -f "$target" 2>/dev/null)
    [ -z "$REAL_PATH" ] && continue

    # Check if target is a symlink/junction pointing elsewhere
    if [ -L "$target" ] || [ -L "$(dirname "$target")" ]; then
        # The path contains a symlink — check where it leads
        LINK_TARGET=$(readlink -f "$target" 2>/dev/null)

        # Block if the symlink leads to system directories
        if echo "$LINK_TARGET" | grep -qiE '^/(mnt/[a-z]/Users|mnt/[a-z]/Windows|mnt/[a-z]/Program|home$|etc$|usr$|var$|boot$)'; then
            echo "BLOCKED: rm would traverse symlink/junction to system directory" >&2
            echo "  Target: $target" >&2
            echo "  Resolves to: $LINK_TARGET" >&2
            echo "  This could destroy Windows system files (NTFS junction traversal)." >&2
            echo "  Reference: GitHub Issue #36339" >&2
            exit 2
        fi
    fi

    # Also block rm on Windows system mount points directly
    if echo "$REAL_PATH" | grep -qiE '^/mnt/[a-z]/(Users|Windows|Program Files)'; then
        echo "BLOCKED: rm targets Windows system directory" >&2
        echo "  Path: $REAL_PATH" >&2
        exit 2
    fi
done

exit 0
