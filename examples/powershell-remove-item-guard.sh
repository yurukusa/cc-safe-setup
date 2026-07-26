#!/bin/bash
# powershell-remove-item-guard.sh — Block PowerShell recursive deletion that traverses junctions
#
# Solves: Remove-Item -Recurse -Force on pnpm worktrees traverses NTFS junctions,
#         permanently deleting user profile folders and source code (#29249).
#         Also prevents wholesale C: drive deletion via PowerShell (#41708).
#
# How it works: Intercepts shell-tool commands containing PowerShell Remove-Item patterns.
#   Hard-blocks when -Recurse targets system directories, user profiles, or paths
#   that could traverse NTFS junctions (node_modules, .pnpm). For -Recurse -Force on
#   any other absolute drive/UNC path it asks for confirmation instead of blocking —
#   the case that destroyed ~34 client video files in #64310 (D:\Clientes\...) where
#   -Force bypassed the Recycle Bin and no confirmation was requested.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash|PowerShell"
#   Claude Code's PowerShell tool is separate from Bash. Register with
#   matcher "Bash|PowerShell" so Remove-Item run through the native
#   PowerShell tool is inspected too — a Bash-only matcher never fires
#   on the PowerShell tool (#69397). The command is read from
#   tool_input.command, which both tools populate.

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

# Confirm before -Recurse -Force on any other absolute drive/UNC path.
# The hard blocks above only cover system, junction, and home targets. The case
# that destroyed ~34 client video files in #64310 was Remove-Item -Recurse -Force on
# an ordinary data path (D:\Clientes\...) — none of the above matched, -Force bypassed
# the Recycle Bin, and no confirmation was requested (SSD/TRIM made it unrecoverable).
# Use "ask" rather than a hard block so routine build/dependency cleanup just gets one
# confirmation instead of being denied; relative paths (./build) don't trigger at all.
# CAUTION: under bypassPermissions an "ask" decision is silently auto-approved
# (#77212), so this confirmation never appears there — exactly the unattended
# runs where #64310-style deletions happen. Do not rely on this branch as a
# hard stop under auto-approve modes; the hard blocks above (exit 2) still hold.
if echo "$COMMAND" | grep -qiE '\-Force' \
   && echo "$COMMAND" | grep -qiE '[A-Za-z]:[\\/]|\\\\[A-Za-z0-9]'; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Confirm: Remove-Item -Recurse -Force on an absolute path. -Force bypasses the Recycle Bin and is unrecoverable on SSD/TRIM. Verify the target path is correct (and that any move/copy finished) before deleting (#64310)."}}'
  exit 0
fi
