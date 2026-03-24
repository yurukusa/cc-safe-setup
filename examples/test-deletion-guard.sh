#!/bin/bash
# ================================================================
# test-deletion-guard.sh — Block deletion of test assertions
# ================================================================
# PURPOSE:
#   Claude sometimes deletes or comments out failing tests instead
#   of fixing the underlying code. This hook detects when an Edit
#   to a test file removes test assertions.
#
# TRIGGER: PreToolUse  MATCHER: "Edit"
#
# Born from: https://github.com/anthropics/claude-code/issues/38050
#   "Claude skips/deletes tests instead of fixing them"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check test files
case "$FILE" in
    *test*|*spec*|*__tests__*|*_test.go|*_test.py|*Test.java|*Test.kt)
        ;;
    *)
        exit 0
        ;;
esac

OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
[ -z "$OLD" ] && exit 0

# Count test assertions in old vs new
count_tests() {
    echo "$1" | grep -cE '(it\(|test\(|describe\(|def test_|#\[test\]|@Test|assert|expect\(|should\b)' 2>/dev/null || echo 0
}

OLD_COUNT=$(count_tests "$OLD")
NEW_COUNT=$(count_tests "$NEW")

if [ "$OLD_COUNT" -gt 0 ] && [ "$NEW_COUNT" -lt "$OLD_COUNT" ]; then
    REMOVED=$((OLD_COUNT - NEW_COUNT))
    echo "WARNING: This edit removes $REMOVED test assertion(s) from $FILE." >&2
    echo "If tests are failing, fix the code instead of deleting tests." >&2
    echo "Old assertions: $OLD_COUNT → New assertions: $NEW_COUNT" >&2
fi

exit 0
