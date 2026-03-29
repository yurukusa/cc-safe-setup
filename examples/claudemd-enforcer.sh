#!/bin/bash
#
# TRIGGER: PostToolUse  MATCHER: "Bash"
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
RESULT=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if [ "${CC_REQUIRE_TESTS:-0}" = "1" ]; then
    if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
        LAST_TEST=$(stat -c %Y coverage/.last-run.json 2>/dev/null || stat -c %Y test-results 2>/dev/null || echo 0)
        NOW=$(date +%s)
        if [ "$LAST_TEST" -eq 0 ] || [ $((NOW - LAST_TEST)) -gt 600 ]; then
            echo "⚠ CLAUDE.md VIOLATION: Committed without running tests first" >&2
        fi
    fi
fi
if [ -n "${CC_ENFORCED_BRANCH}" ]; then
    if echo "$COMMAND" | grep -qE "git\s+push.*${CC_ENFORCED_BRANCH}"; then
        echo "⚠ CLAUDE.md VIOLATION: Pushed to protected branch '${CC_ENFORCED_BRANCH}'" >&2
    fi
fi
if [ "${CC_NO_FORCE_PUSH:-1}" = "1" ]; then
    if echo "$COMMAND" | grep -qE 'git\s+push.*--force'; then
        echo "⚠ CLAUDE.md VIOLATION: Force push detected" >&2
    fi
fi
MAX_FILES=${CC_MAX_FILES_PER_COMMIT:-20}
if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
    STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
    if [ "$STAGED" -gt "$MAX_FILES" ]; then
        echo "⚠ CLAUDE.md VIOLATION: Committing $STAGED files (max: $MAX_FILES)" >&2
    fi
fi
if echo "$COMMAND" | grep -qE '^\s*git\s+add'; then
    STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)
    for f in $STAGED_FILES; do
        [ -f "$f" ] || continue
        if grep -qE 'console\.log\(|debugger;|print\(' "$f" 2>/dev/null; then
            echo "⚠ CLAUDE.md REMINDER: Debug statements found in staged file: $f" >&2
            break
        fi
    done
fi
exit 0
