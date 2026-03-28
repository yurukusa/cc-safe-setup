#!/bin/bash
# ================================================================
# check-test-exists.sh — Warn when editing code without a test file
# ================================================================
# PURPOSE:
#   When Claude edits a source file, check if a corresponding test
#   file exists. If not, warn that the change is untested. This
#   catches the common pattern where Claude modifies code but skips
#   adding or updating tests.
#
#   Supports: JS/TS (*.test.*, *.spec.*), Python (*_test.py, test_*),
#   Go (*_test.go), Ruby (*_spec.rb), Java (*Test.java)
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
#         "command": "~/.claude/hooks/check-test-exists.sh"
#       }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Skip test files themselves, configs, docs
case "$FILE" in
    *.test.*|*.spec.*|*_test.*|test_*|*Test.java|*_spec.rb) exit 0 ;;
    *.md|*.json|*.yaml|*.yml|*.toml|*.cfg|*.ini|*.env*) exit 0 ;;
    *.css|*.scss|*.html|*.svg|*.png|*.jpg) exit 0 ;;
esac

DIR=$(dirname "$FILE")
BASE=$(basename "$FILE")
NAME="${BASE%.*}"
EXT="${BASE##*.}"

# Check for corresponding test file
FOUND=0
case "$EXT" in
    js|jsx|ts|tsx|mjs)
        for pattern in "$DIR/$NAME.test.$EXT" "$DIR/$NAME.spec.$EXT" "$DIR/__tests__/$NAME.$EXT" "$DIR/../__tests__/$BASE"; do
            [ -f "$pattern" ] && FOUND=1 && break
        done
        ;;
    py)
        for pattern in "$DIR/test_$BASE" "$DIR/${NAME}_test.py" "$DIR/tests/test_$BASE" "$DIR/../tests/test_$BASE"; do
            [ -f "$pattern" ] && FOUND=1 && break
        done
        ;;
    go)
        [ -f "$DIR/${NAME}_test.go" ] && FOUND=1
        ;;
    rb)
        for pattern in "$DIR/${NAME}_spec.rb" "$DIR/../spec/${NAME}_spec.rb"; do
            [ -f "$pattern" ] && FOUND=1 && break
        done
        ;;
    java)
        for pattern in "$DIR/${NAME}Test.java" "$DIR/../test/${NAME}Test.java"; do
            [ -f "$pattern" ] && FOUND=1 && break
        done
        ;;
    *)
        exit 0  # Unknown language, skip
        ;;
esac

if [ "$FOUND" -eq 0 ]; then
    echo "⚠ No test file found for $BASE" >&2
    echo "  Consider adding tests before committing this change." >&2
fi

exit 0
