#!/bin/bash
# session-summary-stop.sh — Print session change summary on stop
#
# Solves: No quick way to see what Claude changed during a session.
#         Git diff shows code changes but not the full picture.
#
# How it works: Stop hook that runs `git diff --stat` and outputs
#               a summary of all modified files since the session started.
#
# Usage: Add to settings.json as a Stop hook
#
# {
#   "hooks": {
#     "Stop": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-summary-stop.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)

# Only run if in a git repo
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    exit 0
fi

# Get change summary
CHANGES=$(git diff --stat HEAD 2>/dev/null)
STAGED=$(git diff --cached --stat 2>/dev/null)
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)

if [ -n "$CHANGES" ] || [ -n "$STAGED" ] || [ "$UNTRACKED" -gt 0 ]; then
    echo "--- Session Change Summary ---" >&2
    if [ -n "$CHANGES" ]; then
        echo "Modified:" >&2
        echo "$CHANGES" | head -20 >&2
    fi
    if [ -n "$STAGED" ]; then
        echo "Staged:" >&2
        echo "$STAGED" | head -10 >&2
    fi
    if [ "$UNTRACKED" -gt 0 ]; then
        echo "Untracked files: $UNTRACKED" >&2
    fi
    echo "---" >&2
fi

exit 0
