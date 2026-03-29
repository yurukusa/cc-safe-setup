#!/bin/bash
# file-recycle-bin.sh — Move deleted files to recycle bin instead of permanent deletion
#
# Solves: No undo for file operations during Claude Code sessions (#39949).
#         When Claude deletes or overwrites files, they're gone permanently
#         unless git tracked. This hook intercepts rm commands and moves
#         files to a session recycle bin.
#
# How it works: PreToolUse hook on Bash that intercepts rm commands,
#   copies target files to .claude/recycle-bin/ before allowing deletion.
#   Restore with: cp .claude/recycle-bin/<file> <original-path>
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only intercept rm commands (not rm -rf which destructive-guard handles)
if ! echo "$COMMAND" | grep -qE '^\s*rm\s'; then
  exit 0
fi

# Skip if destructive-guard would catch it (rm -rf /, rm -rf ~, etc.)
if echo "$COMMAND" | grep -qE 'rm\s+(-[rf]+\s+)*(/|~|\$HOME)'; then
  exit 0  # Let destructive-guard handle these
fi

# Extract file paths from rm command (simple extraction)
FILES=$(echo "$COMMAND" | sed 's/^[[:space:]]*rm[[:space:]]*//' | sed 's/-[rfiv]*//g' | tr ' ' '\n' | grep -v '^$' | grep -v '^-')

BIN_DIR=".claude/recycle-bin"
mkdir -p "$BIN_DIR"

for FILE in $FILES; do
  if [ -f "$FILE" ]; then
    BASENAME=$(basename "$FILE")
    TIMESTAMP=$(date +%H%M%S)
    cp "$FILE" "$BIN_DIR/${TIMESTAMP}-${BASENAME}" 2>/dev/null || true
    echo "Backed up: $FILE -> $BIN_DIR/${TIMESTAMP}-${BASENAME}" >&2
  fi
done

# Allow the rm to proceed (files are backed up)
exit 0
