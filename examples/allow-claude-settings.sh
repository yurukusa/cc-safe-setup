#!/bin/bash
# allow-claude-settings.sh — PermissionRequest hook
# Trigger: PermissionRequest
# Matcher: Edit|Write
#
# Auto-approves writes to .claude/ configuration files.
# Use this in isolated environments (containers, VMs) where
# bypassPermissions is enabled but .claude/ writes still prompt.
#
# See: https://github.com/anthropics/claude-code/issues/36044
# See: https://github.com/anthropics/claude-code/issues/37765
#
# WARNING: Only use in environments where you trust Claude's edits
# to your configuration. In shared or production environments,
# keep the default prompts.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Allow .claude/ writes (settings, rules, agents, skills, hooks)
if echo "$FILE_PATH" | grep -qE '\.claude/'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      permissionDecision: "allow",
      permissionDecisionReason: "Allowed: .claude/ directory (isolated environment)"
    }
  }'
  exit 0
fi

exit 0
