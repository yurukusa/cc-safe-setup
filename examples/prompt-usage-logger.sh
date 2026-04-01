set -euo pipefail
INPUT=$(cat)
LOG_FILE="${CC_PROMPT_LOG:-/tmp/claude-usage-log.txt}"
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt | .[0:100]' 2>/dev/null || echo "(parse error)")
echo "$(date -u +%H:%M:%S) prompt=$PROMPT" >> "$LOG_FILE"
printf '%s\n' "$INPUT"
