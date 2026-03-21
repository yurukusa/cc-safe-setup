#!/bin/bash
# enforce-tests.sh — Warn when source files are edited without tests
#
# Solves: CLAUDE.md says "every change needs tests" but Claude ignores it
#
# GitHub Issue: #36920
#
# Usage: Add to settings.json as a PostToolUse hook on "Edit|Write"
#
# Customize TEST_PATTERN for your project's test file naming convention.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Only check source files (customize these patterns)
case "$FILE_PATH" in
    *.py)
        # Python: src/foo.py → test_foo.py or tests/test_foo.py
        BASENAME=$(basename "$FILE_PATH" .py)
        DIR=$(dirname "$FILE_PATH")
        if [[ "$BASENAME" != test_* ]] && [[ "$DIR" != */test* ]]; then
            # Look for corresponding test file
            TEST_CANDIDATES=(
                "${DIR}/test_${BASENAME}.py"
                "${DIR}/tests/test_${BASENAME}.py"
                "tests/test_${BASENAME}.py"
                "test_${BASENAME}.py"
            )
            FOUND=0
            for tc in "${TEST_CANDIDATES[@]}"; do
                if [ -f "$tc" ]; then FOUND=1; break; fi
            done
            if (( FOUND == 0 )); then
                echo "" >&2
                echo "NOTE: Edited $FILE_PATH but no test file found." >&2
                echo "Consider adding tests (CLAUDE.md rule)." >&2
            fi
        fi
        ;;
    *.js|*.ts)
        BASENAME=$(basename "$FILE_PATH" | sed 's/\.\(js\|ts\)$//')
        if [[ "$BASENAME" != *.test ]] && [[ "$BASENAME" != *.spec ]]; then
            DIR=$(dirname "$FILE_PATH")
            if [ ! -f "${DIR}/${BASENAME}.test.js" ] && [ ! -f "${DIR}/${BASENAME}.spec.ts" ] && [ ! -f "${DIR}/__tests__/${BASENAME}.test.js" ]; then
                echo "" >&2
                echo "NOTE: Edited $FILE_PATH but no test file found." >&2
            fi
        fi
        ;;
esac

exit 0
