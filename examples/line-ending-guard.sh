#!/bin/bash
# ================================================================
# line-ending-guard.sh — Warn on CRLF/LF mismatch
# ================================================================
# PURPOSE:
#   Claude Code outputs LF line endings. On Windows/WSL, files may
#   use CRLF. Editing a CRLF file with LF content creates mixed
#   line endings, causing test failures, script errors, and git
#   noise. Especially common in .bat, .cmd, .ps1 files.
#
# TRIGGER: PreToolUse
# MATCHER: "Write|Edit"
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]] && exit 0
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

# Check if existing file uses CRLF
if head -c 1000 "$FILE" 2>/dev/null | od -c | grep -q '\\r\\n'; then
    echo "WARNING: $FILE uses CRLF line endings. Claude outputs LF." >&2
    echo "  This may create mixed line endings. Consider:" >&2
    echo "  - Setting .gitattributes: *.bat text eol=crlf" >&2
    echo "  - Running: unix2dos $FILE (after edit)" >&2
fi

exit 0
