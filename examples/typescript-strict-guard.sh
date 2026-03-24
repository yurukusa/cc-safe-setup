#!/bin/bash
# typescript-strict-guard.sh — Warn when tsconfig.json strict mode is disabled
# TRIGGER: PostToolUse  MATCHER: "Edit"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in */tsconfig.json|tsconfig.json) ;; *) exit 0 ;; esac
NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
[ -z "$NEW" ] && exit 0
if echo "$NEW" | grep -q '"strict"' && echo "$NEW" | grep -q 'false'; then
  echo "WARNING: TypeScript strict mode being disabled in tsconfig.json." >&2
  echo "Strict mode catches bugs at compile time. Think twice." >&2
fi
exit 0
