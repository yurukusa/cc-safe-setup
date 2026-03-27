#!/bin/bash
# variable-expansion-guard.sh — Block destructive commands with shell variable expansion
#
# Solves: Claude running rm -rf "${LOCALAPPDATA}/" where Bash expands the
# variable to a real system path, deleting 50+ app folders.
# See: https://github.com/anthropics/claude-code/issues/39460
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
#         "if": "Bash(rm *)",
#         "command": "~/.claude/hooks/variable-expansion-guard.sh"
#       }]
#     }]
#   }
# }
#
# The "if" field (v2.1.85+) limits this to rm commands only.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check destructive commands
echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?(rm|mv|cp|chmod|chown)\b' || exit 0

# Detect shell variable patterns in arguments
# $VAR, ${VAR}, $(command), `command`
if echo "$COMMAND" | grep -qE '\$\{[A-Z_]+\}|\$[A-Z_]{2,}'; then
    VAR=$(echo "$COMMAND" | grep -oE '\$\{[A-Z_]+\}|\$[A-Z_]{2,}' | head -1)
    echo "BLOCKED: Destructive command uses shell variable $VAR" >&2
    echo "Variables may expand to system paths (e.g., \$LOCALAPPDATA → C:/Users/.../AppData/Local)" >&2
    echo "Use explicit paths instead of variables in destructive commands." >&2
    exit 2
fi

# Detect command substitution in rm arguments
if echo "$COMMAND" | grep -qE '^\s*(sudo\s+)?rm\b.*(\$\(|`)'; then
    echo "BLOCKED: rm with command substitution detected" >&2
    echo "The substituted path could expand to a system directory." >&2
    exit 2
fi

exit 0
