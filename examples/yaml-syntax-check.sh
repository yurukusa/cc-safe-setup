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
