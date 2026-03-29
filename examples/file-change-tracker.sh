#!/bin/bash
# file-change-tracker.sh — Track all file modifications in a session
#
# Solves: Hard to know which files Claude modified during a session.
#         Git diff shows the final state but not the order of changes.
#         This log shows every Write/Edit in chronological order.
#
# How it works: PostToolUse hook for Write/Edit that logs each change.
#               Creates a timestamped changelog at ~/.claude/session-changes.log
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/file-change-tracker.sh" }]
#     }, {
#       "matcher": "Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/file-change-tracker.sh" }]
#     }]
#   }
# }
#
# View changes: cat ~/.claude/session-changes.log
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[ -z "$TOOL" ] && exit 0

LOG_FILE="${CC_CHANGE_LOG:-$HOME/.claude/session-changes.log}"
TIMESTAMP=$(date '+%H:%M:%S')

case "$TOOL" in
    Write)
        FILEPATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        CONTENT_LEN=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null | wc -c)
        echo "$TIMESTAMP WRITE $FILEPATH (${CONTENT_LEN}B)" >> "$LOG_FILE" 2>/dev/null
        ;;
    Edit)
        FILEPATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        OLD_LEN=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null | wc -c)
        NEW_LEN=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | wc -c)
        echo "$TIMESTAMP EDIT  $FILEPATH (${OLD_LEN}B → ${NEW_LEN}B)" >> "$LOG_FILE" 2>/dev/null
        ;;
esac

exit 0
