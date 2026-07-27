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
