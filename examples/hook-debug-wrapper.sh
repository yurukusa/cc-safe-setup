#!/bin/bash
# ================================================================
# hook-debug-wrapper.sh — Debug wrapper for any Claude Code hook
# ================================================================
# PURPOSE:
#   Wraps any existing hook script and logs its input, output,
#   exit code, and execution time. Invaluable for debugging hooks
#   that silently fail or produce unexpected results.
#
# USAGE:
#   Instead of:
#     "command": "~/.claude/hooks/destructive-guard.sh"
#   Use:
#     "command": "~/.claude/hooks/hook-debug-wrapper.sh ~/.claude/hooks/destructive-guard.sh"
#
#   Or set CC_HOOK_DEBUG=1 to log all hooks (requires wrapper for each).
#
# WHAT IT LOGS:
#   - Timestamp
#   - Hook script path
#   - Input JSON (truncated to 500 chars)
#   - Exit code
#   - stdout (truncated)
#   - stderr (truncated)
#   - Execution time in ms
#
# LOG LOCATION: ~/.claude/hook-debug.log
#
# TRIGGER: Any (wraps any hook)
# MATCHER: Any
# ================================================================

HOOK_SCRIPT="$1"
DEBUG_LOG="${CC_HOOK_DEBUG_LOG:-$HOME/.claude/hook-debug.log}"

if [[ -z "$HOOK_SCRIPT" ]] || [[ ! -f "$HOOK_SCRIPT" ]]; then
    echo "Usage: hook-debug-wrapper.sh <hook-script>" >&2
    exit 0
fi

# Read input
INPUT=$(cat)

# Record start time
START_MS=$(($(date +%s%N) / 1000000))

# Run the actual hook, capturing all output
STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)
echo "$INPUT" | bash "$HOOK_SCRIPT" > "$STDOUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?

END_MS=$(($(date +%s%N) / 1000000))
ELAPSED=$((END_MS - START_MS))

# Read outputs
STDOUT_CONTENT=$(cat "$STDOUT_FILE")
STDERR_CONTENT=$(cat "$STDERR_FILE")
rm -f "$STDOUT_FILE" "$STDERR_FILE"

# Log
HOOK_NAME=$(basename "$HOOK_SCRIPT")
INPUT_PREVIEW=$(echo "$INPUT" | head -c 500)
STDOUT_PREVIEW=$(echo "$STDOUT_CONTENT" | head -c 300)
STDERR_PREVIEW=$(echo "$STDERR_CONTENT" | head -c 300)

mkdir -p "$(dirname "$DEBUG_LOG")" 2>/dev/null
{
    echo "=== $(date -Iseconds) === ${HOOK_NAME} ==="
    echo "exit: ${EXIT_CODE} (${ELAPSED}ms)"
    if [[ -n "$STDERR_PREVIEW" ]]; then
        echo "stderr: ${STDERR_PREVIEW}"
    fi
    if [[ -n "$STDOUT_PREVIEW" ]]; then
        echo "stdout: ${STDOUT_PREVIEW}"
    fi
    echo "input: ${INPUT_PREVIEW}"
    echo ""
} >> "$DEBUG_LOG"

# Pass through the original output
if [[ -n "$STDOUT_CONTENT" ]]; then
    echo "$STDOUT_CONTENT"
fi
if [[ -n "$STDERR_CONTENT" ]]; then
    echo "$STDERR_CONTENT" >&2
fi

exit "$EXIT_CODE"
