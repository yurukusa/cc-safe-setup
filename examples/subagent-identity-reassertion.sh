#!/bin/bash
# subagent-identity-reassertion.sh — Re-assert subagent identity to mitigate parent-context leak
#
# Solves: Subagent identity leak (Issue #55488, v2.1.126 regression).
#         When DM'd directly via team chat UI, the subagent dispatch may fall
#         back to the parent's conversation context — surfacing parent
#         identity and history that the subagent should not have access to.
#
# How it works: PreToolUse hook on Agent that emits a stderr REMINDER right
#   before every Agent spawn. The reminder makes parent-context leaks visible
#   in the operator's terminal (early detection signal) and surfaces the
#   recommended operational workaround (relay through parent rather than
#   DM the subagent directly) on each dispatch.
#
# Trade-off: Adds a stderr line per Agent call. Use only if your threat model
#   includes sensitive parent-session context that subagents should not see.
#   Issue #55488 workarounds 1-3 (explicit re-assertion / parent relay /
#   context audit) are usually sufficient and cheaper.
#
# Reference: Issue #55488 (yurukusa Comment 5/2 14:27 JST)
#   https://github.com/anthropics/claude-code/issues/55488
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"

set -euo pipefail

INPUT=$(cat)

# Apply only on Agent tool calls. Tolerate malformed JSON by treating
# unparseable input as a non-Agent fast path (silent exit 0).
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ "$TOOL" = "Agent" ] || exit 0

# Extract subagent type / name for the reminder
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)
SUBAGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.name // empty' 2>/dev/null || true)

ROLE_LABEL="subagent"
[ -n "$SUBAGENT_TYPE" ] && ROLE_LABEL="$SUBAGENT_TYPE"
[ -n "$SUBAGENT_NAME" ] && ROLE_LABEL="$SUBAGENT_NAME ($SUBAGENT_TYPE)"

# Emit reminder to stderr — Claude Code surfaces this in the operator's terminal
cat >&2 <<EOF
[subagent-identity-reassertion] Spawning $ROLE_LABEL — Issue #55488 mitigation
  - Operational guard: route sensitive DMs through the parent agent, not directly to this subagent
  - Audit: ensure parent context does not contain secrets the subagent must not see
  - Recovery: if leak observed, send "Your role is $ROLE_LABEL. Confirm." to lock identity for the turn
EOF

exit 0
