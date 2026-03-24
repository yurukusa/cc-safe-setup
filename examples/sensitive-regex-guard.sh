#!/bin/bash
# sensitive-regex-guard.sh — Warn on ReDoS-vulnerable regex patterns
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
# Detect common ReDoS patterns: nested quantifiers
if echo "$CONTENT" | grep -qE '\([^)]*[+*][^)]*\)[+*]|\(\.\*\)\+'; then
  echo "WARNING: Possible ReDoS-vulnerable regex detected." >&2
  echo "Nested quantifiers like (a+)+ or (.*)+ can cause catastrophic backtracking." >&2
fi
exit 0
