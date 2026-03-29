#!/bin/bash
# auto-approve-compound-git.sh — PermissionRequest hook
# Trigger: PermissionRequest
# Matcher: Bash
#
# Auto-approves compound git commands that the built-in permission
# system fails to match. The wildcard pattern Bash(git:*) only matches
# simple commands like "git status" but not "cd src && git log" or
# "git add file.txt && git commit -m 'fix'".
#
# This hook runs AFTER the built-in permission check fails (because
# compound commands don't match Bash(git:*)), and approves if ALL
# individual commands in the chain are safe git operations.
#
# See: https://github.com/anthropics/claude-code/issues/30519
# See: https://github.com/anthropics/claude-code/issues/16561
#
# TRIGGER: PermissionRequest  MATCHER: ""

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Split on && ; || and check each part
# Only approve if EVERY component is a safe git command or cd
SAFE=true
while IFS= read -r part; do
  # Trim whitespace
  part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$part" ] && continue

  # Allow: cd, git (read ops), git add, git commit, git stash, git branch
  if echo "$part" | grep -qE '^(cd |git (status|log|diff|show|branch|tag|stash|add|commit|fetch|pull|checkout|switch|restore|rebase|merge|cherry-pick|remote|config) )'; then
    continue
  fi
  # Allow simple git commands without args
  if echo "$part" | grep -qE '^git (status|log|diff|show|branch|tag|stash|fetch|pull)$'; then
    continue
  fi
  # Any non-git command = not safe
  SAFE=false
  break
done < <(echo "$COMMAND" | tr '&' '\n' | tr ';' '\n' | tr '|' '\n')

if [ "$SAFE" = "true" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      permissionDecision: "allow",
      permissionDecisionReason: "Allowed: compound git command (all parts are safe git ops)"
    }
  }'
fi

exit 0
