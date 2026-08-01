#!/bin/bash
# read-only-mode.sh — Block all file modifications and destructive commands
#
# Solves: Claude Code making unauthorized changes during test-only or
# audit-only tasks, even when CLAUDE.md says "no changes" (#41063)
#
# Why a hook instead of CLAUDE.md: CLAUDE.md instructions are advisory —
# the model can ignore them under pressure (e.g., when it finds a bug
# and instinctively wants to fix it). Hooks are enforced at the process
# level and cannot be bypassed.
#
# Toggle: Set CLAUDE_READONLY=1 to enable, unset to disable
#   export CLAUDE_READONLY=1   # enable read-only mode
#   unset CLAUDE_READONLY      # disable
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [
#       {
#         "matcher": "Write|Edit|NotebookEdit",
#         "hooks": [{ "type": "command", "command": "~/.claude/hooks/read-only-mode.sh" }]
#       },
#       {
#         "matcher": "Bash",
#         "hooks": [{ "type": "command", "command": "~/.claude/hooks/read-only-mode.sh" }]
#       }
#     ]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Write|Edit|NotebookEdit|Bash"

# Only active when CLAUDE_READONLY=1
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-read-only-mode-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [read-only-mode]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

[[ "${CLAUDE_READONLY:-}" != "1" ]] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Block all file write tools
case "$TOOL" in
    Write|Edit|NotebookEdit)
        echo "BLOCKED: Read-only mode is active. Document this in your report instead of modifying files." >&2
        exit 2
        ;;
esac

# For Bash, block destructive commands but allow reads
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

# Allow read-only commands
if echo "$CMD" | grep -qE '^\s*(ls|cat|head|tail|less|more|wc|find|grep|rg|ag|git\s+(log|show|diff|status|branch)|pwd|echo|printf|date|whoami|env|which|type|file|stat|du|df|uname|hostname|id|test|true|false|\[)'; then
    exit 0
fi

# Block database mutations
if echo "$CMD" | grep -qiE '\b(ALTER|DROP|TRUNCATE|INSERT|UPDATE|DELETE|CREATE|GRANT|REVOKE)\b'; then
    echo "BLOCKED: Read-only mode — database mutations are not allowed. Document the needed change in your report." >&2
    exit 2
fi

# Block Docker/service mutations
if echo "$CMD" | grep -qiE 'docker\s+(restart|stop|rm|build|compose\s+up)|systemctl\s+(start|stop|restart|enable|disable)|service\s+\S+\s+(start|stop|restart)'; then
    echo "BLOCKED: Read-only mode — service mutations are not allowed. Document the needed change in your report." >&2
    exit 2
fi

# Block file writes via shell
if echo "$CMD" | grep -qE '(>\s|>>|tee\s|mv\s|cp\s|rm\s|mkdir\s|rmdir\s|chmod\s|chown\s|ln\s|touch\s|sed\s+-i|install\s|pip\s+install|npm\s+(install|publish|unpublish)|yarn\s+add|apt\s+install|brew\s+install)'; then
    echo "BLOCKED: Read-only mode — file/package modifications are not allowed. Document what needs to change in your report." >&2
    exit 2
fi

# Allow everything else (mostly read commands)
exit 0
