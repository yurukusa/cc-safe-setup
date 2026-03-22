#!/bin/bash
# scope-guard.sh — Block file operations outside the project directory
#
# Solves: Claude Code deleting files on Desktop, in ~/Applications,
# or anywhere outside the working directory (#36233, #36339)
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/scope-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ "$TOOL" != "Bash" ]] && exit 0
[[ -z "$CMD" ]] && exit 0

# Skip string output commands
if echo "$CMD" | grep -qE '^\s*(echo|printf|cat\s*<<)'; then
    exit 0
fi

# Check for destructive commands with paths outside project
if echo "$CMD" | grep -qE '\brm\b.*(-[a-zA-Z]*[rf]|--(recursive|force))'; then
    # Block absolute paths
    if echo "$CMD" | grep -qE '\brm\b[^|;]*\s+/[a-zA-Z]'; then
        echo "BLOCKED: rm with absolute path" >&2
        echo "Command: $CMD" >&2
        exit 2
    fi
    # Block home directory paths
    if echo "$CMD" | grep -qE '\brm\b[^|;]*\s+~/'; then
        echo "BLOCKED: rm targeting home directory" >&2
        exit 2
    fi
    # Block parent directory escapes
    if echo "$CMD" | grep -qE '\brm\b[^|;]*\s+\.\./'; then
        echo "BLOCKED: rm escaping project directory" >&2
        exit 2
    fi
fi

# Block targeting well-known user/system directories
if echo "$CMD" | grep -qiE '\b(rm|del|Remove-Item)\b.*(Desktop|Applications|Documents|Downloads|Library|Keychain|\.aws|\.ssh)'; then
    echo "BLOCKED: targeting system/user directory" >&2
    exit 2
fi

exit 0
