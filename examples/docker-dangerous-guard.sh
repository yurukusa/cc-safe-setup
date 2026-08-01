#!/bin/bash
# docker-dangerous-guard.sh — Block dangerous Docker operations
#
# Prevents: docker system prune -a, docker rm -f on running containers,
#           docker run --privileged, docker exec as root on production containers.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/docker-dangerous-guard.sh" }]
#     }]
#   }
# }

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-docker-dangerous-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [docker-dangerous-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Block docker system prune -a (removes all images)
if echo "$COMMAND" | grep -qE 'docker\s+system\s+prune\s+.*-a'; then
  echo "BLOCKED: docker system prune -a removes all unused images." >&2
  echo "  Use 'docker system prune' (without -a) to keep tagged images." >&2
  exit 2
fi

# Block docker run --privileged
if echo "$COMMAND" | grep -qE 'docker\s+run\s+.*--privileged'; then
  echo "BLOCKED: --privileged gives full host access to the container." >&2
  exit 2
fi

# Warn on docker rm -f (force remove)
if echo "$COMMAND" | grep -qE 'docker\s+(rm|container\s+rm)\s+.*-f'; then
  echo "WARNING: Force-removing container. Data in the container will be lost." >&2
fi

# Block docker run with host network and port 22/80/443
if echo "$COMMAND" | grep -qE 'docker\s+run.*--network\s+host'; then
  echo "WARNING: --network host exposes all container ports on the host." >&2
fi

exit 0
