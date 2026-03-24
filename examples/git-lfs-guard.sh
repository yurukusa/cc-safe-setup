#!/bin/bash
# ================================================================
# git-lfs-guard.sh — Suggest Git LFS for large binary files
# ================================================================
# PURPOSE:
#   Claude sometimes git-adds large binary files (images, videos,
#   compiled binaries) that bloat the repository. This hook warns
#   when staging files larger than a threshold and suggests LFS.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   CC_LFS_THRESHOLD_KB=500  (warn above 500KB)
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

echo "$COMMAND" | grep -qE '^\s*git\s+add' || exit 0

THRESHOLD="${CC_LFS_THRESHOLD_KB:-500}"

# Extract files being added
FILES=$(echo "$COMMAND" | sed 's/git add//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$')

for f in $FILES; do
    [ -f "$f" ] || continue
    SIZE_KB=$(du -k "$f" 2>/dev/null | cut -f1)
    [ -z "$SIZE_KB" ] && continue

    if [ "$SIZE_KB" -gt "$THRESHOLD" ]; then
        echo "WARNING: $f is ${SIZE_KB}KB — consider Git LFS." >&2
        echo "  git lfs track '$f' && git add .gitattributes $f" >&2
    fi
done

exit 0
