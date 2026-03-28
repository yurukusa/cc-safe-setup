#!/bin/bash
# hook-stdout-sanitizer.sh — Prevent hook stdout from corrupting tool results
#
# Solves: Worktree path corrupted by hook stdout (#40262).
#         When a hook writes to stdout (instead of stderr), the output
#         gets concatenated into tool results like file paths, causing
#         corruption (e.g., worktree path becomes "/path/to/repo{hookJSON}").
#
# How it works: Wraps another hook script, redirecting all of its stdout
#   to stderr. Only valid JSON hookSpecificOutput is sent to stdout.
#   This prevents accidental stdout pollution.
#
# Usage: Wrap any existing hook:
#   Original: "command": "bash ~/.claude/hooks/my-hook.sh"
#   Wrapped:  "command": "bash ~/.claude/hooks/hook-stdout-sanitizer.sh ~/.claude/hooks/my-hook.sh"
#
# Or use as a template for writing safe hooks.
#
# TRIGGER: Any (wrapper for other hooks)
# MATCHER: Any

TARGET_HOOK="$1"
shift

if [ -z "$TARGET_HOOK" ] || [ ! -f "$TARGET_HOOK" ]; then
    echo "Usage: hook-stdout-sanitizer.sh <path-to-hook.sh>" >&2
    exit 0
fi

# Capture stdin (tool input)
TOOL_INPUT=$(cat)

# Run the target hook, capturing stdout and stderr separately
STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)
echo "$TOOL_INPUT" | bash "$TARGET_HOOK" "$@" > "$STDOUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?

# Forward stderr (safe — always goes to user)
cat "$STDERR_FILE" >&2

# Only forward stdout if it looks like valid hookSpecificOutput JSON
STDOUT_CONTENT=$(cat "$STDOUT_FILE")
if [ -n "$STDOUT_CONTENT" ]; then
    # Check if it's valid JSON with hookSpecificOutput
    if echo "$STDOUT_CONTENT" | jq -e '.hookSpecificOutput' &>/dev/null 2>&1 || \
       echo "$STDOUT_CONTENT" | jq -e '.permissionDecision' &>/dev/null 2>&1 || \
       echo "$STDOUT_CONTENT" | jq -e '.systemMessage' &>/dev/null 2>&1; then
        # Valid hook output — forward to stdout
        echo "$STDOUT_CONTENT"
    else
        # Not valid hook JSON — redirect to stderr to prevent corruption
        echo "⚠ hook-stdout-sanitizer: redirected non-JSON stdout to stderr" >&2
        echo "$STDOUT_CONTENT" >&2
    fi
fi

# Clean up
rm -f "$STDOUT_FILE" "$STDERR_FILE"

exit $EXIT_CODE
