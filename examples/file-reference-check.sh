#!/bin/bash
# ================================================================
# file-reference-check.sh — Verify referenced file paths exist
# ================================================================
# PURPOSE:
#   Claude sometimes writes import/require/include statements that
#   reference files that don't exist (hallucinated paths). This
#   hook checks Write/Edit output for common file reference patterns
#   and warns if the referenced files are missing.
#
#   Catches: import './missing', require('../gone'), #include "nope.h"
#
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/file-reference-check.sh"
#       }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

DIR=$(dirname "$FILE")
EXT="${FILE##*.}"
MISSING=0

# Extract relative imports based on language
case "$EXT" in
    js|jsx|ts|tsx|mjs)
        # import ... from './path' or require('./path')
        grep -oE "(from|require\()\s*['\"]\.\.?/[^'\"]+['\"]" "$FILE" 2>/dev/null | \
        grep -oE "\.\.?/[^'\"]*" | while read -r ref; do
            # Try with common extensions
            FOUND=0
            for ext in "" ".js" ".ts" ".jsx" ".tsx" ".mjs" "/index.js" "/index.ts"; do
                [ -f "$DIR/$ref$ext" ] && FOUND=1 && break
            done
            if [ "$FOUND" -eq 0 ]; then
                echo "⚠ Missing import: $ref (from $FILE)" >&2
                MISSING=$((MISSING + 1))
            fi
        done
        ;;
    py)
        # from .module import ... (relative imports)
        grep -oE "^from \.\S+ import" "$FILE" 2>/dev/null | \
        grep -oE "\.\S+" | sed 's/\./\//g; s|^/||' | while read -r ref; do
            [ -f "$DIR/$ref.py" ] || [ -d "$DIR/$ref" ] || {
                echo "⚠ Missing relative import: $ref (from $FILE)" >&2
            }
        done
        ;;
esac

exit 0
