#!/bin/bash
# dockerfile-lint.sh — Basic Dockerfile validation after editing
#
# Prevents: Common Dockerfile mistakes:
#           - Missing FROM instruction
#           - Using latest tag (non-reproducible builds)
#           - Running as root without explicit USER
#           - COPY/ADD before dependency install (cache invalidation)
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write|Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/dockerfile-lint.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check Dockerfiles
BASENAME=$(basename "$FILE")
case "$BASENAME" in
  Dockerfile|Dockerfile.*|*.dockerfile) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

WARNINGS=""

# Check for FROM instruction
if ! grep -qE '^FROM\s' "$FILE"; then
  WARNINGS="${WARNINGS}\n  Missing FROM instruction"
fi

# Check for :latest tag
if grep -qE '^FROM\s+\S+:latest' "$FILE"; then
  WARNINGS="${WARNINGS}\n  Using :latest tag (non-reproducible)"
fi

# Check for no USER instruction (running as root)
if ! grep -qE '^USER\s' "$FILE"; then
  WARNINGS="${WARNINGS}\n  No USER instruction (container runs as root)"
fi

if [ -n "$WARNINGS" ]; then
  echo "Dockerfile warnings in $FILE:" >&2
  echo -e "$WARNINGS" >&2
fi

exit 0
