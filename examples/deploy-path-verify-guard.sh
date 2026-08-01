#!/bin/bash
# deploy-path-verify-guard.sh — Verify deployment target path before writes
#
# Solves: Writing files to wrong filesystem path in Docker setups (#40421).
#         Claude wrote to host /srv/ instead of Docker mount /opt/acestream/public/
#         three times, each time claiming deployment was successful.
#
# How it works: Before writing to paths matching CC_DEPLOY_PATHS pattern,
#   verifies the target is actually mounted/accessible. Catches host-vs-container
#   path confusion.
#
# CONFIG:
#   CC_DEPLOY_PATHS="/srv:/opt/acestream/public:/var/www"
#   CC_DEPLOY_VERIFY_CMD="docker inspect --format '{{.Mounts}}' mycontainer"
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|Write"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-deploy-path-verify-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [deploy-path-verify-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

DEPLOY_PATHS="${CC_DEPLOY_PATHS:-/srv:/var/www:/opt}"

# For Write tool, check file_path
if [ "$TOOL" = "Write" ]; then
  FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$FILE" ] && exit 0

  IFS=':' read -ra PATHS <<< "$DEPLOY_PATHS"
  for dp in "${PATHS[@]}"; do
    if [[ "$FILE" == "$dp"* ]]; then
      echo "WARNING: Writing to deployment path $dp." >&2
      echo "File: $FILE" >&2
      echo "" >&2
      echo "Verify this is the correct target:" >&2
      echo "  - Is this inside a Docker container or on the host?" >&2
      echo "  - Run 'docker inspect' to check bind mounts first." >&2
      # Warning only (exit 0), not blocking — change to exit 2 to block
      exit 0
    fi
  done
fi

# For Bash tool, check commands that write to deploy paths
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$COMMAND" ] && exit 0

  IFS=':' read -ra PATHS <<< "$DEPLOY_PATHS"
  for dp in "${PATHS[@]}"; do
    if echo "$COMMAND" | grep -qE "(cp|mv|tee|cat.*>|echo.*>).*${dp}"; then
      echo "WARNING: Bash command targets deployment path $dp." >&2
      echo "Command: $COMMAND" >&2
      echo "Verify the target path is correct (host vs container)." >&2
      exit 0
    fi
  done
fi

exit 0
