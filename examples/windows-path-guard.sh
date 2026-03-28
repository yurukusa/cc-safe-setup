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

# Check the entire command for Windows system paths
# This catches both direct paths and quoted paths with spaces
WINDOWS_SYSTEM='/mnt/[a-z]/(Users|Windows|Program Files|Program)'
if echo "$COMMAND" | grep -qiE "$WINDOWS_SYSTEM"; then
    echo "BLOCKED: rm targets Windows system directory" >&2
    echo "  Command contains a Windows system path reference." >&2
    echo "  This could destroy system files via NTFS junction traversal." >&2
    echo "  Reference: GitHub Issue #36339" >&2
    exit 2
fi

# Check if any rm target is a symlink pointing to system directories
for target in $(echo "$COMMAND" | grep -oE '/[^ ";\|&]+' | head -10); do
    [ -L "$target" ] || [ -L "$(dirname "$target" 2>/dev/null)" ] || continue
    LINK_TARGET=$(readlink -f "$target" 2>/dev/null)
    [ -z "$LINK_TARGET" ] && continue
    if echo "$LINK_TARGET" | grep -qiE "^/(mnt/[a-z]/(Users|Windows|Program)|home$|etc$|usr$|var$)"; then
        echo "BLOCKED: rm would traverse symlink/junction to system directory" >&2
        echo "  Target: $target → $LINK_TARGET" >&2
        exit 2
    fi
done

exit 0
