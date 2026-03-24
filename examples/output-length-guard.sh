#!/bin/bash
# output-length-guard.sh — Warn when tool output is very large
# TRIGGER: PostToolUse  MATCHER: ""
# Checks tool output size and warns when it's consuming too much context
INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)
if [ -n "$OUTPUT" ]; then
    LEN=${#OUTPUT}
    if [ "$LEN" -gt 50000 ]; then
        echo "WARNING: Tool output is ${LEN} chars. Large outputs consume context rapidly." >&2
        echo "Consider using head/tail/grep to limit output, or redirect to a file." >&2
    fi
fi
exit 0
