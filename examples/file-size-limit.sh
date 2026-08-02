#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-file-size-limit-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [file-size-limit]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
LEN=${#CONTENT}
MAX="${CC_MAX_FILE_SIZE:-1048576}"
if [ "$LEN" -gt "$MAX" ]; then
  echo "BLOCKED: File content is ${LEN} bytes (limit: ${MAX})." >&2
  exit 2
fi
exit 0
