#!/bin/bash
# move-delete-sequence-guard.sh — Detect move+delete sequences that cause data loss
#
# Solves: Agent moves files to a temp location, then deletes the parent directory,
#   effectively destroying the moved files' original context and siblings.
#   - #49129: mv files to /tmp && rm -rf parent/ — lost 50GB of data
#   - #49792: Opus 4.7 moves files, then deletes the source directory
#
# Pattern detected:
#   mv <source> <dest> && rm -rf <source_parent>
#   mv <source> <dest> ; rm -rf <source_parent>
#   mv <source> <dest> || rm -rf <source_parent>
#   Any compound command containing both mv and rm -r on related paths
#
# This is distinct from rm-safety-net.sh (blocks rm on critical paths)
# and bulk-file-delete-guard.sh (blocks large recursive deletes).
# This hook specifically targets the mv+rm compound pattern.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check compound commands that contain both mv and rm
if ! echo "$COMMAND" | grep -qE '\bmv\s' || ! echo "$COMMAND" | grep -qE '\brm\s'; then
    exit 0
fi

# Extract mv source directory and rm target, check for overlap
# Pattern: mv <src> <dst> [&&;||] rm [-rf] <target>
# We check if the rm target is a parent of, or the same as, the mv source

# Get all mv source paths (first arg after mv and optional flags)
MV_SOURCES=$(echo "$COMMAND" | grep -oP '\bmv\s+(-[a-zA-Z]+\s+)*\K\S+' 2>/dev/null || true)
# Get all rm targets
RM_TARGETS=$(echo "$COMMAND" | grep -oP '\brm\s+(-[a-zA-Z]+\s+)*\K\S+' 2>/dev/null || true)

[ -z "$MV_SOURCES" ] && exit 0
[ -z "$RM_TARGETS" ] && exit 0

# Normalize: get parent directory of mv source
for mv_src in $MV_SOURCES; do
    mv_parent=$(dirname "$mv_src" 2>/dev/null || echo "")
    [ -z "$mv_parent" ] && continue

    for rm_target in $RM_TARGETS; do
        # Check if rm target matches the mv source's parent or the mv source itself
        # Normalize trailing slashes
        rm_clean="${rm_target%/}"
        mv_parent_clean="${mv_parent%/}"
        mv_src_clean="${mv_src%/}"

        # Case 1: rm deletes the parent of the moved file
        if [ "$rm_clean" = "$mv_parent_clean" ]; then
            echo "BLOCKED: Move+delete sequence detected — rm target ($rm_target) is parent of mv source ($mv_src)" >&2
            echo "This pattern destroys sibling files. Move files individually instead." >&2
            echo "Command: $COMMAND" >&2
            echo "" >&2
            echo "See: https://github.com/anthropics/claude-code/issues/49129" >&2
            exit 2
        fi

        # Case 2: rm deletes the exact path that was moved from
        if [ "$rm_clean" = "$mv_src_clean" ]; then
            # mv a dir then rm -rf the same dir — likely the user moved the dir,
            # but rm -rf on the source after mv is suspicious if recursive
            if echo "$COMMAND" | grep -qE "rm\s+.*-[rRf]*[rR].*$rm_target|rm\s+.*-[rRf]*[rR]\s+$rm_target"; then
                echo "BLOCKED: Move+delete sequence detected — rm -r on the same path as mv source ($mv_src)" >&2
                echo "If the directory was already moved, rm -r should not be needed." >&2
                echo "Command: $COMMAND" >&2
                echo "" >&2
                echo "See: https://github.com/anthropics/claude-code/issues/49129" >&2
                exit 2
            fi
        fi

        # Case 3: rm deletes an ancestor directory of the mv source
        if echo "$mv_src_clean" | grep -qE "^${rm_clean}/"; then
            echo "BLOCKED: Move+delete sequence detected — rm target ($rm_target) is ancestor of mv source ($mv_src)" >&2
            echo "This pattern destroys the source tree. Use targeted operations instead." >&2
            echo "Command: $COMMAND" >&2
            echo "" >&2
            echo "See: https://github.com/anthropics/claude-code/issues/49129" >&2
            exit 2
        fi
    done
done

exit 0
