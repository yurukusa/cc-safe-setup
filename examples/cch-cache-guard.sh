#!/bin/bash
# cch-cache-guard.sh — Block reads of Claude session files to prevent cache poisoning
#
# Solves: When Claude reads its own JSONL session files or proxy logs,
# the `cch=` billing hash substitution permanently breaks prompt cache
# for the entire session. Every subsequent turn pays full cache cost.
#
# Root cause: The CLI mutates historical tool results by substituting
# `cch=` billing hashes, invalidating the cache prefix.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Related: https://github.com/anthropics/claude-code/issues/40652

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Block commands that read Claude's own session files or billing logs
if printf '%s' "$CMD" | grep -qE '\.(jsonl|log)' && \
   printf '%s' "$CMD" | grep -qiE '(claude|session|billing|transcript)'; then
    echo '{"decision": "block", "reason": "Blocked: reading Claude session/billing files can poison prompt cache via cch= substitution. Use an external terminal instead."}'
    exit 0
fi

exit 0
