#!/bin/bash
# tool-file-logger.sh — Log file paths from Read/Write/Edit to stderr
#
# Solves: "No indication of WHICH file for READ tool" (#21151 — 180 reactions)
#         Users must expand every Read/Write/Edit to see the file path.
#         This hook shows the file path in the collapsed view.
#
# Output format:
#   [Read: src/components/App.tsx]
#   [Write: package.json]
#   [Edit: src/utils/helpers.ts]
#
# TRIGGER: PostToolUse
# MATCHER: "Read|Write|Edit"
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Read|Write|Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/tool-file-logger.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

# Extract file path from tool input
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Show just the filename for brevity, full path available in expanded view
BASENAME=$(basename "$FILE")
DIR=$(dirname "$FILE")

# For paths inside home directory, show relative path
if echo "$DIR" | grep -q "^$HOME"; then
  RELDIR=$(echo "$DIR" | sed "s|^$HOME|~|")
  echo "[$TOOL: $RELDIR/$BASENAME]" >&2
else
  echo "[$TOOL: $FILE]" >&2
fi

exit 0
