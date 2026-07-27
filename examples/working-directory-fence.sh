#!/bin/bash
# ================================================================
# working-directory-fence.sh — Block file operations outside CWD
# ================================================================
# PURPOSE:
#   Prevents Claude Code from reading, writing, or editing files
#   outside the current working directory tree. Catches the common
#   problem where Claude wanders to a stale copy of the project
#   on a different drive or directory.
#
# TRIGGER: PreToolUse
# MATCHER: "Read|Edit|Write"
#
# WHY THIS MATTERS:
#   Claude sometimes ignores explicit directory instructions and
#   operates on files in completely different locations (e.g.,
#   working on C:\Users\old-copy instead of D:\projects\current).
#   This leads to edits being applied to the wrong files with
#   no indication to the user.
#
# WHAT IT DOES:
#   Extracts file_path from the tool input. If the resolved path
#   is outside the current working directory, blocks with exit 2.
#
# CONFIGURATION:
#   CC_FENCE_ALLOW — colon-separated list of additional allowed
#     directories (e.g., "/tmp:/home/user/.config")
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41850
# ================================================================

set -u

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

CWD=$(pwd)

# Resolve the file path to absolute
# Handle ~ expansion
FILE_PATH=$(printf '%s' "$FILE_PATH" | sed "s|^~|$HOME|")

# Convert to absolute path if relative
case "$FILE_PATH" in
    /*) ;; # already absolute
    *)  FILE_PATH="${CWD}/${FILE_PATH}" ;;
esac

# Normalize (remove .., trailing slashes)
# Use realpath if available, fallback to simple check
if command -v realpath >/dev/null 2>&1; then
    # realpath may fail if file doesn't exist yet (Write), so use -m
    RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || printf '%s' "$FILE_PATH")
else
    RESOLVED="$FILE_PATH"
fi

# Check if the path is inside CWD
case "$RESOLVED" in
    "${CWD}"*) exit 0 ;; # Inside CWD — allowed
esac

# Check additional allowed directories
if [ -n "${CC_FENCE_ALLOW:-}" ]; then
    IFS=':' read -ra ALLOWED <<< "$CC_FENCE_ALLOW"
    for dir in "${ALLOWED[@]}"; do
        case "$RESOLVED" in
            "${dir}"*) exit 0 ;; # Inside allowed dir
        esac
    done
fi

# Also allow /tmp (commonly used for scratch files)
case "$RESOLVED" in
    /tmp*) exit 0 ;;
esac

printf 'BLOCKED: File operation outside working directory.\n' >&2
printf '\n' >&2
printf '  File:    %s\n' "$RESOLVED" >&2
printf '  CWD:     %s\n' "$CWD" >&2
printf '\n' >&2
printf 'Claude is trying to access a file outside the current project.\n' >&2
printf 'If this is intentional, set CC_FENCE_ALLOW to include the path.\n' >&2
exit 2
