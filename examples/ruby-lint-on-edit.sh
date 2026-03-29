#!/bin/bash
# ================================================================
# ruby-lint-on-edit.sh — Run RuboCop after editing Ruby files
#
# Detects Ruby file edits and runs RuboCop for style/lint checking.
# Warns on issues but doesn't block (exit 0).
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "if": "Edit(*.rb) || Write(*.rb)",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/ruby-lint-on-edit.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != *.rb ]] && exit 0

# Check if rubocop is available
if command -v rubocop &>/dev/null; then
    RESULT=$(rubocop --format simple "$FILE" 2>&1)
    if echo "$RESULT" | grep -q "offense"; then
        echo "RuboCop issues in $(basename "$FILE"):" >&2
        echo "$RESULT" | grep -E "^[CWE]:" | head -5 >&2
    fi
fi

exit 0
