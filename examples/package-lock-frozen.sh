#!/bin/bash
# package-lock-frozen.sh — Block modifications to lockfiles
#
# Prevents: Unintended lockfile changes that cause merge conflicts
#           and dependency drift. Claude should use npm ci, not npm install.
#
# Blocks: Edit/Write to package-lock.json, yarn.lock, pnpm-lock.yaml
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

BASENAME=$(basename "$FILE")
case "$BASENAME" in
  package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|poetry.lock|Gemfile.lock|composer.lock)
    echo "BLOCKED: Direct modification of lockfile '$BASENAME'." >&2
    echo "  Use the package manager to update dependencies instead." >&2
    exit 2
    ;;
esac

exit 0
