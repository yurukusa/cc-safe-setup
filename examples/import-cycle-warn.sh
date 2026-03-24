#!/bin/bash
# ================================================================
# import-cycle-warn.sh — Detect potential circular imports
# ================================================================
# PURPOSE:
#   Claude adds imports without considering dependency cycles.
#   After an edit that adds an import/require, check if the
#   target file imports back from the edited file.
#
# TRIGGER: PostToolUse  MATCHER: "Edit"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
[ -z "$NEW" ] && exit 0

# Extract newly added imports
BASENAME=$(basename "$FILE" | sed 's/\.[^.]*$//')

# JS/TS: import ... from './target' or require('./target')
IMPORTS=$(echo "$NEW" | grep -oE "(from\s+['\"]\.\/[^'\"]+|require\(['\"]\.\/[^'\"]+)" | grep -oE '\./[^"'"'"']+' | sed 's/^\.\///')

# Python: from .target import or import target
if [ -z "$IMPORTS" ]; then
    IMPORTS=$(echo "$NEW" | grep -oE "from\s+\.\w+" | awk '{print $2}' | sed 's/^\.//')
fi

[ -z "$IMPORTS" ] && exit 0

DIR=$(dirname "$FILE")
for imp in $IMPORTS; do
    # Check if target imports back
    for ext in .js .ts .jsx .tsx .py .mjs; do
        TARGET="$DIR/$imp$ext"
        [ -f "$TARGET" ] || continue
        if grep -qE "(from\s+['\"].*${BASENAME}|import\s+.*${BASENAME}|require.*${BASENAME})" "$TARGET" 2>/dev/null; then
            echo "WARNING: Potential circular import detected." >&2
            echo "  $FILE imports $imp" >&2
            echo "  $TARGET imports back from $BASENAME" >&2
            break
        fi
    done
done

exit 0
