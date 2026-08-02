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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-package-lock-frozen-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [package-lock-frozen]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
