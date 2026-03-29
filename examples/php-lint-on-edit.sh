#!/bin/bash
# ================================================================
# php-lint-on-edit.sh — Run PHP syntax check after editing PHP files
#
# Uses php -l for syntax validation. Warns on errors.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write",
#       "if": "Edit(*.php) || Write(*.php)",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/php-lint-on-edit.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != *.php ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0

# Run PHP syntax check
if command -v php &>/dev/null; then
    RESULT=$(php -l "$FILE" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "PHP syntax error in $(basename "$FILE"):" >&2
        echo "$RESULT" | head -3 >&2
    fi
fi

exit 0
