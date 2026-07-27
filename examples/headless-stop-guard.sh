#!/bin/bash
# headless-stop-guard.sh — Skip Stop hooks in headless (-p) mode
#
# Solves: Stop hook causes empty result in print mode (#38651).
#         Any Stop hook (even no-op) causes `claude -p` to return
#         empty string instead of the model's response.
#
# How it works: Detects headless mode via parent process inspection
#   and exits immediately, preventing the Stop hook from interfering
#   with result collection.
#
# TRIGGER: Stop
# MATCHER: ""
#
# Usage: Use as a wrapper around your actual Stop hook:
# {
#   "hooks": {
#     "Stop": [{
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/headless-stop-guard.sh ~/.claude/hooks/my-stop-hook.sh" }]
#     }]
#   }
# }
#
# Or set CC_HEADLESS=1 in your wrapper script before `claude -p`.

# Method 1: Environment variable (most reliable)
[ "$CC_HEADLESS" = "1" ] && exit 0

# Method 2: Parent process detection
PARENT_CMD=$(ps -o args= -p $PPID 2>/dev/null || true)
if echo "$PARENT_CMD" | grep -qE '\bclaude\b.*\s-p\b'; then
    exit 0
fi

# Not headless — run the wrapped hook if provided
TARGET="$1"
if [ -n "$TARGET" ] && [ -f "$TARGET" ]; then
    shift
    cat | bash "$TARGET" "$@"
    exit $?
fi

exit 0
