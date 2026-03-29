#!/bin/bash
# deploy-guard.sh — Block deploy commands when uncommitted changes exist
#
# Solves: Claude deploying without committing, causing changes to
# silently revert on next sync (#37314, #34674)
#
# Detects: rsync, scp, deploy scripts, firebase deploy, vercel,
# netlify deploy, fly deploy, railway, heroku push
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/deploy-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Detect deploy commands
if ! echo "$COMMAND" | grep -qiE '(rsync|scp|deploy|firebase\s+deploy|vercel|netlify\s+deploy|fly\s+deploy|railway\s+up|git\s+push\s+heroku|kubectl\s+(apply|create|delete|rollout)|terraform\s+(apply|destroy))'; then
    exit 0
fi

# Must be in a git repo
git rev-parse --git-dir &>/dev/null || exit 0

# Check for uncommitted changes
DIRTY=$(git status --porcelain 2>/dev/null | head -1)
if [[ -n "$DIRTY" ]]; then
    echo "BLOCKED: Uncommitted changes detected. Commit before deploying." >&2
    echo "" >&2
    echo "Dirty files:" >&2
    git status --short 2>/dev/null | head -10 >&2
    echo "" >&2
    echo "Run: git add -A && git commit -m 'pre-deploy checkpoint'" >&2
    exit 2
fi

exit 0
