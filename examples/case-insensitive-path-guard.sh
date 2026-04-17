#!/bin/bash
# case-insensitive-path-guard.sh — Detect path case mismatches on case-insensitive filesystems
#
# Solves: Claude Code resolving paths with wrong case on macOS APFS (case-insensitive),
#   causing rm -rf to destroy unintended directories
#   - #48792: rm -rf WebstormProjects/ destroyed webstormprojects/ (10 years of work)
#   - #49102: Same APFS bug, second catastrophic loss in 48 hours
#
# How it works:
#   For rm/mv/cp commands targeting paths under $HOME, resolves the ACTUAL
#   filesystem path and compares case. If the specified path exists only via
#   case-insensitive matching (e.g., "Projects" matches "projects/"), blocks
#   the command because the user likely intended a different directory.
#
# Platform: macOS only (APFS case-insensitive is default). On Linux (ext4, case-sensitive),
#   the guard exits cleanly since case mismatches simply won't resolve.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check destructive commands
echo "$COMMAND" | grep -qE '\b(rm|mv|cp)\s' || exit 0

# Skip if not macOS (Linux filesystems are case-sensitive by default)
if [ "$(uname)" != "Darwin" ]; then
    exit 0
fi

# Extract target paths from destructive commands
# Handles: rm -rf path, mv path dest, cp -r path dest
TARGETS=""

# rm: all non-flag arguments
if echo "$COMMAND" | grep -qE '\brm\s'; then
    TARGETS=$(echo "$COMMAND" | grep -oP '\brm\s+(-[a-zA-Z]+\s+)*\K[^\s;&|]+(\s+[^\s;&|]+)*' 2>/dev/null || true)
fi

# mv: first non-flag argument (source)
if echo "$COMMAND" | grep -qE '\bmv\s'; then
    MV_TARGET=$(echo "$COMMAND" | grep -oP '\bmv\s+(-[a-zA-Z]+\s+)*\K\S+' 2>/dev/null || true)
    TARGETS="$TARGETS $MV_TARGET"
fi

[ -z "$TARGETS" ] && exit 0

# Expand ~ to $HOME
TARGETS=$(echo "$TARGETS" | sed "s|~|$HOME|g")

for target in $TARGETS; do
    # Skip flags
    echo "$target" | grep -q '^-' && continue

    # Skip safe disposable paths
    echo "$target" | grep -qE '(node_modules|\.cache|__pycache__|/tmp/|dist/|build/)' && continue

    # Only check paths under home directory (most risk)
    echo "$target" | grep -qE "^($HOME|~)" || continue

    # Resolve the canonical path using the filesystem
    # On case-insensitive APFS, /Users/me/Projects resolves even if actual is /Users/me/projects
    CANONICAL=$(python3 -c "
import os, sys
p = os.path.expanduser('$target')
# Walk up to find the longest existing prefix
check = p
while check and not os.path.exists(check):
    check = os.path.dirname(check)
if not check:
    sys.exit(0)
# Get the real path (canonical case)
real = os.path.realpath(check)
# Get the suffix that was beyond the existing part
suffix = p[len(check):]
print(real + suffix)
" 2>/dev/null || echo "")

    [ -z "$CANONICAL" ] && continue

    # Compare: if the specified path differs in case from the canonical path
    if [ "$target" != "$CANONICAL" ] && [ "${target,,}" = "${CANONICAL,,}" ] 2>/dev/null; then
        echo "BLOCKED: Case mismatch detected on case-insensitive filesystem" >&2
        echo "  Specified: $target" >&2
        echo "  Actual:    $CANONICAL" >&2
        echo "  On macOS APFS, these resolve to the SAME directory." >&2
        echo "  This mismatch has caused catastrophic data loss (#48792, #49102)." >&2
        echo "  Verify the path case matches the actual filesystem before proceeding." >&2
        exit 2
    fi
done

exit 0
