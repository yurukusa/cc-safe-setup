#!/bin/bash
# docker-prune-guard.sh — Warn before docker system prune
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bdocker\s+system\s+prune'; then
  echo "WARNING: docker system prune removes stopped containers, unused networks, dangling images." >&2
  echo "Add --filter to limit scope, or use docker image prune for images only." >&2
fi
exit 0
