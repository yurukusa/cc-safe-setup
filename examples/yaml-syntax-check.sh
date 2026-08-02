#!/bin/bash
# yaml-syntax-check.sh — Validate YAML after editing
#
# Prevents: Broken YAML configs (docker-compose, CI pipelines, k8s manifests).
#           YAML indentation errors are invisible until deployment fails.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write|Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/yaml-syntax-check.sh" }]
#     }]
#   }
# }

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-yaml-syntax-check-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [yaml-syntax-check]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check YAML files
case "$FILE" in
  *.yml|*.yaml) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

# Try python yaml parser
if command -v python3 >/dev/null 2>&1; then
  ERROR=$(python3 -c "
import yaml, sys
try:
    with open('$FILE') as f:
        yaml.safe_load(f)
except yaml.YAMLError as e:
    print(str(e)[:200])
    sys.exit(1)
" 2>&1)
  if [ $? -ne 0 ]; then
    echo "YAML SYNTAX ERROR in $FILE:" >&2
    echo "  $ERROR" >&2
    exit 2
  fi
fi

exit 0
