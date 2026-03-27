#!/bin/bash
# edit-always-allow.sh — Auto-approve all Edit prompts in configured directories
#
# Solves: --dangerously-skip-permissions doesn't bypass Edit prompts
#         (#36192, #36168 — bypass permissions broken since v2.1.78)
#
# Claude Code v2.1.78+ prompts for Edit in .claude/, .git/, .vscode/
# even with bypassPermissions enabled. This PermissionRequest hook
# restores the pre-v2.1.78 behavior for specified directories.
#
# Configure allowed directories via CC_EDIT_ALLOW_DIRS env var:
#   export CC_EDIT_ALLOW_DIRS=".claude/skills:.claude/commands"
# Default: .claude/skills
#
# TRIGGER: PermissionRequest
# MATCHER: "Edit|Write"
#
# Usage:
# {
#   "hooks": {
#     "PermissionRequest": [{
#       "matcher": "Edit|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/edit-always-allow.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only handle Edit/Write
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Configurable allowed directories (colon-separated)
ALLOW_DIRS="${CC_EDIT_ALLOW_DIRS:-.claude/skills}"

# Check if file is in an allowed directory
IFS=':' read -ra DIRS <<< "$ALLOW_DIRS"
for dir in "${DIRS[@]}"; do
  if echo "$FILE" | grep -q "$dir"; then
    echo '{"permissionDecision":"allow"}'
    exit 0
  fi
done

# Not in allowed directories — let the prompt through
exit 0
