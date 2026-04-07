#!/bin/bash
# allow-git-hooks-dir.sh — PermissionRequest hook
# Trigger: PermissionRequest
# Matcher: Edit|Write
#
# Bypasses the built-in protected-directory prompt for .git/hooks/.
# PreToolUse hooks can't do this — they run before built-in checks.
# PermissionRequest runs after, so it can override the prompt.
#
# WARNING: Only allow specific subdirectories you trust.
# Never blanket-allow all of .git/ — that exposes HEAD, config, etc.
#
# TRIGGER: PermissionRequest  MATCHER: ""

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Only allow .git/hooks/ writes (e.g., pre-commit, pre-push)
if echo "$FILE_PATH" | grep -qE '\.git/hooks/[^/]+$'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: {
        behavior: "allow"
      }
    }
  }'
  exit 0
fi

exit 0
