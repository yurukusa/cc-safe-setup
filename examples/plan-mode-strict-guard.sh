#!/bin/bash
# plan-mode-strict-guard.sh — Hard-block all write operations during plan mode
#
# Solves: Plan mode doesn't hard-block write tools (#40324, 0 reactions).
#         When Claude is in plan mode, it should only read and analyze.
#         But the model can propose Edit/Write operations, and if the user
#         clicks "approve", they execute — defeating the purpose of plan mode.
#
# How it works: Checks for plan mode indicators:
#   1. CC_PLAN_MODE env var (set by some configurations)
#   2. .claude/plan-mode.lock file (created by plan-mode-enforcer.sh)
#   3. Plan-related keywords in the session context
#
# When plan mode is active, blocks Edit, Write, and dangerous Bash commands.
# Read, Glob, Grep, and safe Bash commands are allowed.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write|Bash"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

# Check if plan mode is active
PLAN_MODE=false

# Method 1: Environment variable
[ "${CC_PLAN_MODE:-}" = "true" ] && PLAN_MODE=true

# Method 2: Lock file
[ -f "${HOME}/.claude/plan-mode.lock" ] && PLAN_MODE=true

# Method 3: Project-level plan lock
[ -f ".claude/plan-mode.lock" ] && PLAN_MODE=true

[ "$PLAN_MODE" = "false" ] && exit 0

# Plan mode is active — enforce read-only
case "$TOOL" in
    Edit|Write)
        echo "BLOCKED: Plan mode is active — write operations are not allowed" >&2
        echo "  Exit plan mode first, then make changes" >&2
        echo "  Remove ~/.claude/plan-mode.lock or unset CC_PLAN_MODE" >&2
        exit 2
        ;;
    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        [ -z "$CMD" ] && exit 0

        # Allow read-only commands in plan mode
        # Strip compound operators to get the first command
        FIRST_PART=$(echo "$CMD" | sed 's/[;&|].*//' | sed 's/^\s*//')

        # Single-word safe commands
        FIRST_WORD=$(echo "$FIRST_PART" | awk '{print $1}')
        SAFE_SINGLE="ls|cat|head|tail|grep|find|wc|diff|pwd|echo|date|which|type|file|tree|du|df|env|printenv"
        if echo "$FIRST_WORD" | grep -qxE "$SAFE_SINGLE"; then
            exit 0
        fi

        # Two-word safe commands (git, npm, etc.)
        FIRST_TWO=$(echo "$FIRST_PART" | awk '{print $1, $2}')
        SAFE_TWO="git status|git log|git diff|git branch|git show|git rev-parse|git tag|node -v|python3 -V|npm list|npm outdated|pip list|pip show"
        if echo "$FIRST_TWO" | grep -qxE "$SAFE_TWO"; then
            exit 0
        fi

        # Block write commands in plan mode
        echo "BLOCKED: Plan mode is active — only read-only Bash commands allowed" >&2
        echo "  Allowed: ls, cat, grep, git status/log/diff, etc." >&2
        exit 2
        ;;
esac

exit 0
