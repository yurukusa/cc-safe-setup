#!/bin/bash
# decision-warn.sh — Warn and log irreversible operations
#
# Solves: "Why did Claude push to production?" — no decision trail for critical actions
# Detects dangerous operations (git push, rm -rf, database commands) and logs them
# to a decision log for post-incident analysis.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/decision-warn.sh" }]
#     }]
#   }
# }
#
# Output: ~/.claude/decision-log.jsonl
# Each entry logs the command, timestamp, and detected risk category.

set -u

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

LOG_FILE="${HOME}/.claude/decision-log.jsonl"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

RISK=""

# Detect irreversible operations
if echo "$CMD" | grep -qE 'git\s+push'; then
  RISK="git-push"
elif echo "$CMD" | grep -qE 'git\s+reset\s+--hard'; then
  RISK="git-reset-hard"
elif echo "$CMD" | grep -qE 'rm\s+(-rf|--recursive)'; then
  RISK="destructive-delete"
elif echo "$CMD" | grep -qiE '(DROP\s+(TABLE|DATABASE)|TRUNCATE|DELETE\s+FROM)'; then
  RISK="database-destructive"
elif echo "$CMD" | grep -qE 'npm\s+publish'; then
  RISK="npm-publish"
elif echo "$CMD" | grep -qE 'curl\s+.*-X\s*(DELETE|PUT|POST)'; then
  RISK="api-mutation"
fi

[ -z "$RISK" ] && exit 0

printf '{"ts":"%s","risk":"%s","cmd":"%s"}\n' \
  "$TS" "$RISK" "$(echo "$CMD" | head -c 200 | tr '"' "'")" >> "$LOG_FILE"

echo "[DECISION] $RISK: $(echo "$CMD" | head -c 100)" >&2
echo "  → Logged to: $LOG_FILE" >&2

exit 0
