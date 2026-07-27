#!/bin/bash
# ================================================================
# markdown-link-check.sh — Verify local file links in markdown
# ================================================================
# PURPOSE:
#   After Claude edits a markdown file, check that all local file
#   references (relative paths) actually exist. Catches broken
#   links to images, other docs, or code files.
#
# TRIGGER: PostToolUse
# MATCHER: "Edit|Write"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0
echo "$FILE" | grep -qiE '\.md$|\.mdx$' || exit 0
[ -f "$FILE" ] || exit 0

DIR=$(dirname "$FILE")
BROKEN=0

# Extract markdown links: [text](path) — skip URLs and anchors
while IFS= read -r link; do
    # Skip URLs, anchors, and mailto
    echo "$link" | grep -qE '^(https?://|#|mailto:)' && continue
    # Remove anchor part
    CLEAN=$(echo "$link" | sed 's/#.*//')
    [ -z "$CLEAN" ] && continue
    # Resolve relative path
    TARGET="$DIR/$CLEAN"
    if [ ! -e "$TARGET" ]; then
        echo "⚠ Broken link in $FILE: $link" >&2
        BROKEN=$((BROKEN + 1))
    fi
done < <(grep -oE '\]\([^)]+\)' "$FILE" 2>/dev/null | sed 's/\](\(.*\))/\1/')

if [ "$BROKEN" -gt 0 ]; then
    echo "  $BROKEN broken link(s) found." >&2
fi

exit 0
