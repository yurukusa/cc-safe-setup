#!/bin/bash
# output-pii-detect.sh — Detect PII/sensitive data in tool output
# TRIGGER: PostToolUse  MATCHER: ""
OUTPUT=$(cat | jq -r '.tool_result // empty' 2>/dev/null)
[ -z "$OUTPUT" ] && exit 0
# Check for email addresses
if echo "$OUTPUT" | grep -qE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'; then
    echo "NOTE: Email address detected in output" >&2
fi
# Check for IP addresses (non-localhost)
if echo "$OUTPUT" | grep -qE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | grep -vE '127\.0\.0\.1|0\.0\.0\.0|localhost'; then
    echo "NOTE: IP address detected in output" >&2
fi
exit 0
