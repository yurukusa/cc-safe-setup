#!/bin/bash
# self-modify-bypass-guard.sh — Auto-allow .claude/ writes in bypass mode
#
# Solves: Self-modification guard prompts for .claude/ writes even when
#         bypassPermissions is active (#40463). The guard fires before
#         hooks/permissions are evaluated.
#
# How it works: PermissionRequest hook that detects .claude/ write prompts
#   and auto-allows them when the project uses bypassPermissions mode.
#   Exempts security-sensitive paths (settings.json, CLAUDE.md).
#
# TRIGGER: PermissionRequest
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)

# Extract the permission request details
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only handle Edit/Write to .claude/ paths
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

case "$FILE" in
  .claude/*|*/.claude/*) ;;
  *) exit 0 ;;
esac

# Security-sensitive files: always prompt (don't auto-allow)
BASENAME=$(basename "$FILE")
case "$BASENAME" in
  settings.json|settings.local.json|CLAUDE.md)
    # Let the default prompt handle these
    exit 0 ;;
esac

# Check if bypassPermissions is configured
SETTINGS=".claude/settings.json"
if [ -f "$SETTINGS" ]; then
    MODE=$(jq -r '.defaultMode // empty' "$SETTINGS" 2>/dev/null)
    if [ "$MODE" = "bypassPermissions" ]; then
        # Auto-allow: output hookSpecificOutput to approve
        echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","allow":true}}'
        exit 0
    fi
fi

# Not in bypass mode — let default prompt handle it
exit 0
