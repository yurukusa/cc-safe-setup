#!/bin/bash
# plan-mode-enforcer.sh — Hard-enforce Plan Mode read-only constraint
#
# Solves: Plan Mode restrictions bypassed — model performs write/execution
#         operations instead of writing a plan first (#39713)
#
# Root cause: Plan Mode is only a system-reminder, easily overridden by
# tool instructions. This hook enforces it at the tool permission layer.
#
# How it works:
#   - Checks if a state file indicates plan mode is active
#   - If active, blocks all write operations (Edit, Write, Bash with side effects)
#   - Allows read-only operations (Read, Glob, Grep, git status, etc.)
#
# Enable:  touch /tmp/.cc-plan-mode-active
# Disable: rm /tmp/.cc-plan-mode-active
#
# Or use the companion SessionStart hook to auto-detect plan mode.
#
# Usage: PreToolUse hook (matcher: "")
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/plan-mode-enforcer.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

STATE_FILE="/tmp/.cc-plan-mode-active"
[ -f "$STATE_FILE" ] || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Always allow read-only tools
case "$TOOL" in
    Read|Glob|Grep)
        exit 0
        ;;
esac

# Block write tools entirely
case "$TOOL" in
    Edit|Write|NotebookEdit)
        echo "BLOCKED: Plan Mode active — write operations are not allowed" >&2
        echo "  Write your implementation plan first, then exit plan mode." >&2
        exit 2
        ;;
esac

# For Bash, allow read-only commands only
if [ "$TOOL" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$COMMAND" ] && exit 0

    # Extract base command
    BASE=$(echo "$COMMAND" | awk '{print $1}' | sed 's|.*/||')

    # Allowlist: read-only commands
    case "$BASE" in
        cat|head|tail|less|more|wc|grep|rg|ag|find|locate|\
        ls|ll|dir|tree|stat|file|which|whereis|type|realpath|\
        date|uptime|uname|hostname|whoami|id|env|printenv|pwd|\
        df|du|free|top|ps|pgrep|jq|yq|curl|wget)
            exit 0
            ;;
    esac

    # Allow read-only git commands
    if echo "$COMMAND" | grep -qE '^\s*git\s+(status|log|diff|show|branch|remote|tag\s+-l|blame|shortlog|describe|rev-parse|ls-files|ls-tree)\b'; then
        exit 0
    fi

    # Allow npm/pip read-only
    if echo "$COMMAND" | grep -qE '^\s*(npm\s+(ls|list|info|view|outdated)|pip\s+(list|show|freeze)|cargo\s+(tree|doc))'; then
        exit 0
    fi

    # Block everything else in Bash during plan mode
    echo "BLOCKED: Plan Mode active — command execution not allowed: $BASE" >&2
    echo "  Only read-only commands are permitted. Write your plan first." >&2
    exit 2
fi

# Block Agent tool (sub-agents can bypass plan mode)
if [ "$TOOL" = "Agent" ]; then
    echo "BLOCKED: Plan Mode active — sub-agent creation not allowed" >&2
    exit 2
fi

# Allow other tools (TaskCreate, etc.)
exit 0
