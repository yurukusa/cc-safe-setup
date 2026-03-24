#!/bin/bash
# ================================================================
# protect-claudemd.sh — Block edits to CLAUDE.md and settings files
# ================================================================
# PURPOSE:
#   Claude Code sometimes modifies CLAUDE.md, settings.json, or
#   other configuration files without permission. This hook blocks
#   Edit/Write to these critical files.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]]; then
    exit 0
fi

if [[ -z "$FILE" ]]; then
    exit 0
fi

BASENAME=$(basename "$FILE")

# Protected files
case "$BASENAME" in
    CLAUDE.md|.claude.json|settings.json|settings.local.json)
        echo "BLOCKED: Cannot modify configuration file: $BASENAME" >&2
        echo "File: $FILE" >&2
        echo "" >&2
        echo "Configuration files should be edited manually, not by Claude." >&2
        exit 2
        ;;
esac

# Protected directories
if echo "$FILE" | grep -qE '\.claude/(hooks|settings|plugins)/'; then
    echo "BLOCKED: Cannot modify .claude system directory: $FILE" >&2
    exit 2
fi

exit 0
