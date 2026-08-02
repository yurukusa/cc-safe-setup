#!/bin/bash
# repo-visibility-guard.sh — Block repository visibility changes
# Prevents Claude Code from making private repos public (or vice versa).
# Incident: #50353 — Opus 4.7 ran `gh repo edit --visibility public` autonomously,
# exposing a hardcoded private key. Wallet drained $413 in 60-90 seconds.
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/repo-visibility-guard.sh" }]
#     }]
#   }
# }

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-repo-visibility-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [repo-visibility-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Block gh repo edit --visibility (public/private/internal)
if echo "$COMMAND" | grep -qE 'gh\s+repo\s+edit\s+--visibility'; then
    echo "BLOCKED: repository visibility change requires manual confirmation. See #50353." >&2
    exit 2
fi

# Block git push with --set-upstream to unknown remotes (potential exfiltration)
if echo "$COMMAND" | grep -qE 'git\s+remote\s+add\s' && echo "$COMMAND" | grep -qE 'git\s+push'; then
    echo "BLOCKED: adding remote and pushing in one command. Review the remote URL first." >&2
    exit 2
fi

exit 0
