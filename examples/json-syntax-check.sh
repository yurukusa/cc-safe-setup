#!/bin/bash
# ================================================================
# json-syntax-check.sh — Validate JSON files after editing
# ================================================================
# PURPOSE:
#   Claude Code sometimes writes invalid JSON to settings.json,
#   package.json, or tsconfig.json. This hook validates JSON
#   syntax immediately after an edit, before it causes errors.
#
# TRIGGER: PostToolUse
# MATCHER: "Edit|Write"
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0

# Only check JSON files
echo "$FILE" | grep -qiE '\.json$|\.jsonc$' || exit 0

# Skip if file doesn't exist (Write to new file hasn't completed yet)
[ -f "$FILE" ] || exit 0

# Validate JSON
if ! jq empty "$FILE" 2>/dev/null; then
    echo "⚠ Invalid JSON syntax in: $FILE" >&2
    # Show the specific error
    ERROR=$(jq empty "$FILE" 2>&1)
    echo "  Error: $ERROR" >&2
    echo "  Fix this before continuing — broken JSON will cause runtime errors." >&2
fi

exit 0
