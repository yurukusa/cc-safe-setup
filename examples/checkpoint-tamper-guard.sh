#!/bin/bash
# checkpoint-tamper-guard.sh — Block manipulation of hook state/checkpoint files
# Trigger: PreToolUse (Bash, Edit, Write)
# Prevents the model from bypassing hooks by editing their state files
# See: https://github.com/anthropics/claude-code/issues/38841

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Directories/files containing hook state (customize as needed)
PROTECTED_PATTERNS=(
    ".claude/checkpoints"
    ".claude/hook-state"
    ".claude/hooks-disabled"
    "session-call-count"
    "compact-prep-done"
    "subagent-tracker"
)

check_path() {
    local path="$1"
    for pattern in "${PROTECTED_PATTERNS[@]}"; do
        if [[ "$path" == *"$pattern"* ]]; then
            echo "BLOCKED: Cannot manipulate hook state file: $path" >&2
            echo "Hook state files are managed by hooks, not by the model." >&2
            exit 2
        fi
    done
}

# Check Bash commands that write to protected paths
if [ -n "$CMD" ]; then
    for pattern in "${PROTECTED_PATTERNS[@]}"; do
        if echo "$CMD" | grep -qE "(echo|cat|tee|cp|mv|rm|chmod|chown|touch|truncate|>).*${pattern}"; then
            echo "BLOCKED: Cannot manipulate hook state via command" >&2
            exit 2
        fi
    done
fi

# Check Edit/Write file paths
if [ -n "$FILE" ]; then
    check_path "$FILE"
fi

exit 0
