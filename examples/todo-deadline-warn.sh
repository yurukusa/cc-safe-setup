#!/bin/bash
# ================================================================
# todo-deadline-warn.sh — Warn about expired TODO deadlines in edited files
# ================================================================
# PURPOSE:
#   TODOs with dates (e.g., "TODO(2026-03-01): fix this") are often
#   forgotten. When Claude edits a file containing expired TODOs,
#   this hook warns so they can be addressed while the file is open.
#
# TRIGGER: PostToolUse
# MATCHER: "Edit|Write"
#
# DECISION: Advisory only (exit 0). Warns via stderr.
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Skip non-code files
case "$FILE" in
    *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.xml|*.html|*.css) exit 0 ;;
esac

TODAY=$(date +%Y-%m-%d)
EXPIRED=0

# Find TODO/FIXME/HACK with dates like TODO(2026-03-01) or TODO 2026-03-01
while IFS= read -r line; do
    # Extract date from patterns like TODO(2026-01-15) or FIXME 2026-01-15
    DATE=$(echo "$line" | grep -oE '(TODO|FIXME|HACK|XXX)\s*\(?\s*[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
    if [ -n "$DATE" ] && [[ "$DATE" < "$TODAY" ]]; then
        if [ "$EXPIRED" -eq 0 ]; then
            echo "⚠ Expired TODOs in $(basename "$FILE"):" >&2
        fi
        LINENUM=$(echo "$line" | cut -d: -f1)
        CONTENT=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
        echo "  L${LINENUM}: $CONTENT (expired: $DATE)" >&2
        EXPIRED=$((EXPIRED + 1))
    fi
done < <(grep -n -E '(TODO|FIXME|HACK|XXX).*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$FILE" 2>/dev/null)

if [ "$EXPIRED" -gt 0 ]; then
    echo "  $EXPIRED expired TODO(s) — consider resolving while editing this file." >&2
fi

exit 0
