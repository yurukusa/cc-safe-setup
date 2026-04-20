#!/bin/bash
# powershell-remove-item-guard.sh — Block PowerShell recursive deletion that traverses junctions
#
# Solves: Remove-Item -Recurse -Force on pnpm worktrees traverses NTFS junctions,
#         permanently deleting user profile folders and source code (#29249).
#         Also prevents wholesale C: drive deletion via PowerShell (#41708).
#
# How it works: Intercepts Bash commands containing PowerShell Remove-Item patterns.
#   Blocks when -Recurse targets system directories, user profiles, or paths
#   that could traverse NTFS junctions (node_modules, .pnpm).
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check commands containing Remove-Item or ri (PowerShell alias)
echo "$COMMAND" | grep -qiE '(Remove-Item|ri\s|del\s).*-Recurse' || exit 0

# Block if targeting system-critical paths
if echo "$COMMAND" | grep -qiE 'Remove-Item.*-Recurse.*(/|\\)(Users|Windows|Program Files|System32|C:\\|/mnt/c)'; then
  echo '{"decision":"DENY","reason":"Blocked: Remove-Item -Recurse targeting system directory. NTFS junctions can traverse to user profiles (#29249)."}'
  exit 0
fi

# Block if targeting node_modules with -Force (junction traversal risk)
if echo "$COMMAND" | grep -qiE 'Remove-Item.*-Recurse.*-Force.*(node_modules|\.pnpm|worktree)'; then
  echo '{"decision":"DENY","reason":"Blocked: Remove-Item -Recurse -Force on directory with potential NTFS junctions. Use rimraf or manual junction resolution first (#29249)."}'
  exit 0
fi

# Block if targeting home directory patterns
if echo "$COMMAND" | grep -qiE 'Remove-Item.*-Recurse.*(\$HOME|\$env:USERPROFILE|~\/|~\\)'; then
  echo '{"decision":"DENY","reason":"Blocked: Remove-Item -Recurse targeting home directory. Risk of irreversible data loss (#41708)."}'
  exit 0
fi
