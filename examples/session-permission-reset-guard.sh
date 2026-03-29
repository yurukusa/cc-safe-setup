#!/bin/bash
# session-permission-reset-guard.sh — Override session-cached permissions
#
# Solves: Sandbox mode caching session-level permissions (#40384).
#         After approving a command once, sandbox caches the approval
#         for the entire session, bypassing the allow list.
#
# How it works: PreToolUse hook that enforces per-invocation checks
#   for specified commands, regardless of session cache state.
#   Acts as a secondary permission layer outside the caching system.
#
# CONFIG:
#   CC_ALWAYS_CHECK_COMMANDS="git commit:git push:npm publish:cargo install"
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Commands that should always require hook-level check
ALWAYS_CHECK="${CC_ALWAYS_CHECK_COMMANDS:-git commit:git push:npm publish:cargo install:pip install}"

IFS=':' read -ra PATTERNS <<< "$ALWAYS_CHECK"
for pattern in "${PATTERNS[@]}"; do
  # Match the pattern anywhere in the command (including chained commands)
  if echo "$COMMAND" | grep -qiF "$pattern"; then
    echo "HOOK CHECK: '$pattern' detected — hook-level review." >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "This hook enforces per-invocation checks regardless of" >&2
    echo "session permission caching. To allow, remove this pattern" >&2
    echo "from CC_ALWAYS_CHECK_COMMANDS." >&2
    exit 2
  fi
done

exit 0
