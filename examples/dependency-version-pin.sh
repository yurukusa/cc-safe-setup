#!/bin/bash
# ================================================================
# dependency-version-pin.sh — Warn on unpinned dependency versions
# ================================================================
# PURPOSE:
#   Claude adds dependencies with ^ or ~ ranges. Without a lockfile,
#   this means different installs get different versions. This hook
#   warns when package.json is edited to add range-based versions.
#
# TRIGGER: PostToolUse  MATCHER: "Edit"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in */package.json|package.json) ;; *) exit 0 ;; esac

NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
[ -z "$NEW" ] && exit 0

# Check for range specifiers in new content
RANGES=$(echo "$NEW" | grep -oE '"\^[0-9]|"~[0-9]' | wc -l)
if [ "$RANGES" -gt 0 ]; then
    # Check if lockfile exists
    HAS_LOCK=0
    [ -f "package-lock.json" ] && HAS_LOCK=1
    [ -f "yarn.lock" ] && HAS_LOCK=1
    [ -f "pnpm-lock.yaml" ] && HAS_LOCK=1

    if [ "$HAS_LOCK" -eq 0 ]; then
        echo "WARNING: $RANGES dependency(ies) with version ranges (^ or ~) but no lockfile." >&2
        echo "Pin exact versions or add a lockfile for reproducible builds." >&2
    fi
fi

exit 0
