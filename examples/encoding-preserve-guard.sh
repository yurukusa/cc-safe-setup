#!/bin/bash
# ================================================================
# encoding-preserve-guard.sh — Warn when file encoding changes
# ================================================================
# PURPOSE:
#   Claude's Write tool always outputs UTF-8. When editing files
#   that use different encodings (UTF-8 BOM, Latin-1, Shift-JIS),
#   the encoding silently changes, potentially corrupting content.
#   Common in legacy codebases, .csv exports, Windows batch files.
#
# TRIGGER: PreToolUse
# MATCHER: "Write|Edit"
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]] && exit 0
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

# Check for BOM (Byte Order Mark)
if head -c 3 "$FILE" 2>/dev/null | od -An -tx1 | grep -q "ef bb bf"; then
    echo "WARNING: $FILE has UTF-8 BOM. Write tool may strip the BOM." >&2
fi

# Check for non-UTF-8 encoding using file command
ENCODING=$(file -bi "$FILE" 2>/dev/null | grep -oP 'charset=\K\S+')
if [ -n "$ENCODING" ] && [ "$ENCODING" != "utf-8" ] && [ "$ENCODING" != "us-ascii" ]; then
    echo "WARNING: $FILE uses $ENCODING encoding. Write tool outputs UTF-8." >&2
    echo "  This may corrupt non-ASCII characters in the file." >&2
fi

exit 0
