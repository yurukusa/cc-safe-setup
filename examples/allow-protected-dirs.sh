#!/bin/bash
# allow-protected-dirs.sh — PermissionRequest hook
# Trigger: PermissionRequest
# Matcher: Edit|Write
#
# Auto-approves writes to ALL protected directories (.claude/, .git/,
# .vscode/, .idea/). Equivalent to full bypassPermissions for file edits.
#
# USE CASE: Docker containers, CI/CD, disposable VMs where you want
# zero prompts and understand the risks.
#
# WARNING: This is the most permissive PermissionRequest hook possible.
# It bypasses ALL built-in file protection. Do NOT use in shared or
# production environments. Prefer allow-git-hooks-dir.sh or
# allow-claude-settings.sh for targeted bypass.
#
# TRIGGER: PermissionRequest  MATCHER: ""

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

if echo "$FILE_PATH" | grep -qE '\.(claude|git|vscode|idea)/'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      permissionDecision: "allow",
      permissionDecisionReason: "Allowed: protected directory (full bypass)"
    }
  }'
  exit 0
fi

exit 0
