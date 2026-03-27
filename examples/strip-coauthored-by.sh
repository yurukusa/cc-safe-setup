#!/bin/bash
# strip-coauthored-by.sh — Remove or warn about Co-Authored-By trailers
#
# Solves: Claude auto-appending Co-Authored-By to every commit without
# user consent. 489 commits branded without the user wanting it.
# See: https://github.com/anthropics/claude-code/issues/29999
#
# TRIGGER: PreToolUse
# MATCHER: Bash
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(git commit *)",
#         "command": "~/.claude/hooks/strip-coauthored-by.sh"
#       }]
#     }]
#   }
# }
#
# Config: CC_ALLOW_COAUTHOR=1 to allow (default: 0 = block/warn)

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git commit commands
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Check if Co-Authored-By is in the commit message
if echo "$COMMAND" | grep -qiE 'Co-Authored-By.*Claude\|Co-Authored-By.*Anthropic\|Co-Authored-By.*noreply@anthropic'; then
    if [ "${CC_ALLOW_COAUTHOR:-0}" = "1" ]; then
        exit 0  # User explicitly allows
    fi
    echo "⚠ Co-Authored-By trailer detected in commit message" >&2
    echo "  Set CC_ALLOW_COAUTHOR=1 to allow, or remove the trailer." >&2
    echo "  See: https://github.com/anthropics/claude-code/issues/29999" >&2
    # Warn but don't block — user can decide
    exit 0
fi

exit 0
