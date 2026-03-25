#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
RECENT=0
TIMEOUT=${CC_TEST_TIMEOUT:-600}
NOW=$(date +%s)
for marker in coverage/.last-run.json test-results .nyc_output junit.xml; do
    [ -e "$marker" ] || continue
    MTIME=$(stat -c %Y "$marker" 2>/dev/null || echo 0)
    [ $((NOW - MTIME)) -lt "$TIMEOUT" ] && RECENT=1 && break
done
if [ "$RECENT" -eq 0 ]; then
    echo "BLOCKED: No recent test results (within $((TIMEOUT/60)) min)" >&2
    echo "Run your test suite first, then commit." >&2
    exit 2
fi
exit 0
