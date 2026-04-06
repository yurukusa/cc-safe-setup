#!/bin/bash
# activity-logger.sh — Log all tool uses to JSONL for audit and debugging
#
# Solves: "What did Claude do overnight?" — no activity trail after long sessions
# Also useful for: error tracking, cost analysis, compliance auditing
#
# Records every tool call with timestamp, tool name, and key metadata.
# Error patterns in Bash output are flagged for downstream guards.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/activity-logger.sh" }]
#     }]
#   }
# }
#
# Output: ~/.claude/activity-log.jsonl
# Each line is a JSON object with ts, tool, and tool-specific fields.

set -u

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

LOG_FILE="${HOME}/.claude/activity-log.jsonl"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$TOOL" in
  Edit|Write)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    printf '{"ts":"%s","tool":"%s","file":"%s"}\n' "$TS" "$TOOL" "$FILE" >> "$LOG_FILE"
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | head -c 200)
    STDOUT=$(printf '%s' "$INPUT" | jq -r '.stdout // empty' 2>/dev/null | head -c 500)
    EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_result.exit_code // "0"' 2>/dev/null)
    ERROR_PATTERN=""
    if echo "$STDOUT" | grep -qiE '(error|ENOENT|EACCES|EPERM|fatal|panic|segfault)'; then
      ERROR_PATTERN=$(echo "$STDOUT" | grep -oiE '(error|ENOENT|EACCES|EPERM|fatal|panic|segfault)' | head -1)
    fi
    printf '{"ts":"%s","tool":"%s","cmd":"%s","exit_code":%s,"error_pattern":"%s"}\n' \
      "$TS" "$TOOL" "$(echo "$CMD" | tr '"' "'")" "$EXIT_CODE" "$ERROR_PATTERN" >> "$LOG_FILE"
    ;;
  Read)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    printf '{"ts":"%s","tool":"%s","file":"%s"}\n' "$TS" "$TOOL" "$FILE" >> "$LOG_FILE"
    ;;
  *)
    printf '{"ts":"%s","tool":"%s"}\n' "$TS" "$TOOL" >> "$LOG_FILE"
    ;;
esac

exit 0
