#!/bin/bash
# aws-region-guard.sh — Warn when AWS commands target unexpected regions
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*aws\s' || exit 0
EXPECTED="${CC_AWS_REGION:-us-east-1}"
if echo "$COMMAND" | grep -qE '\-\-region\s+(\S+)'; then
  REGION=$(echo "$COMMAND" | grep -oE '\-\-region\s+(\S+)' | awk '{print $2}')
  if [ "$REGION" != "$EXPECTED" ]; then
    echo "WARNING: AWS command targeting $REGION (expected: $EXPECTED)." >&2
    echo "Verify this is the correct region." >&2
  fi
fi
exit 0
