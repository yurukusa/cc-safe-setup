#!/bin/bash
# broad-find-guard.sh — Block overly broad find/locate commands that scan the entire home directory
#
# Solves: Claude Code running `find $HOME` or `find /` which scans all user files,
#         triggering OneDrive/iCloud/Dropbox to download synced files (#51010)
#
# Detects patterns like:
#   find / -name "CLAUDE.md"
#   find ~ -name "*.py"
#   find $HOME -type f
#   find /c/Users/username -name "*.md"
#   locate "CLAUDE.md"
#
# Why: On Windows/macOS, cloud sync folders (OneDrive, iCloud, Dropbox) are
#      under the home directory. A broad `find` traverses them and triggers
#      downloading of ALL synced files — potentially gigabytes of data.
#      Claude Code should only search project-scoped directories.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/broad-find-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Pattern 1: find starting from root
if echo "$COMMAND" | grep -qE 'find\s+/\s'; then
    echo "BLOCKED: find from root (/) scans entire filesystem. Use a project-scoped path instead." >&2
    exit 2
fi

# Pattern 2: find starting from home directory (various forms)
if echo "$COMMAND" | grep -qE 'find\s+(~|\$HOME|/home/[a-zA-Z0-9_]+|/Users/[a-zA-Z0-9_]+|/c/Users/[a-zA-Z0-9_]+)\s'; then
    echo "BLOCKED: find from home directory scans all user files including cloud sync folders (OneDrive/iCloud/Dropbox). Use a specific project path instead." >&2
    exit 2
fi

# Pattern 3: find with -maxdepth 0 or 1 from home is OK (shallow), but deep scans are not
# This pattern catches find ~ without further path restriction
if echo "$COMMAND" | grep -qE 'find\s+(~|\$HOME|/home/|/Users/|/c/Users/)\b' && ! echo "$COMMAND" | grep -qE '\-maxdepth\s+[01]'; then
    echo "BLOCKED: broad find from home directory. Add -maxdepth or use a specific subdirectory to avoid scanning cloud sync folders." >&2
    exit 2
fi

# Pattern 4: locate without project-scoping (scans entire DB)
if echo "$COMMAND" | grep -qE '^\s*locate\s' && ! echo "$COMMAND" | grep -qE 'locate.*--database|locate.*-d\s'; then
    echo "BLOCKED: locate searches the entire filesystem index. Use find with a specific directory instead." >&2
    exit 2
fi

exit 0
