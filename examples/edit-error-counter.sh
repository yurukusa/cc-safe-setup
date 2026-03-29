#!/bin/bash
# ================================================================
# edit-error-counter.sh — Warn when Edit tool fails repeatedly
#
# Solves: Claude making repeated Edit attempts with wrong old_string,
# wasting tokens on "String to replace not found" errors (#3471)
#
# When 3+ Edit errors occur in a row, warns that Claude should
# Read the file first to get the exact current content.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/edit-error-counter.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only track Edit tool
[[ "$TOOL" != "Edit" ]] && exit 0

ERROR=$(echo "$INPUT" | jq -r '.tool_error // empty' 2>/dev/null)
COUNTER_FILE="/tmp/cc-edit-error-counter-$$"

# No error — reset counter
if [[ -z "$ERROR" ]]; then
    rm -f "$COUNTER_FILE" 2>/dev/null
    exit 0
fi

# Check if this is a "not found" error
if echo "$ERROR" | grep -qi "not found\|no match\|does not exist"; then
    COUNT=0
    [[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNTER_FILE"

    if [[ "$COUNT" -ge 3 ]]; then
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // "the file"' 2>/dev/null)
        echo "WARNING: $COUNT consecutive Edit failures on $FILE_PATH." >&2
        echo "The file content may have changed. Read the file first to get the exact current content before editing." >&2
        echo "Tip: Use the Read tool on $FILE_PATH, then copy the exact text you want to replace." >&2
        rm -f "$COUNTER_FILE" 2>/dev/null
    fi
fi

exit 0
