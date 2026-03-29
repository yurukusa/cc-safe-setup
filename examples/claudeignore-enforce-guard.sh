#!/bin/bash
# claudeignore-enforce-guard.sh — Enforce .claudeignore at the tool level
#
# Solves: .claudeignore patterns not blocking Read/Edit/Grep tool calls (#16704).
#         Claude can directly access files listed in .claudeignore via tool calls.
#         This hook enforces ignore rules that the built-in system misses.
#
# How it works: PreToolUse hook on Read/Edit/Write/Grep that checks if the
#   target file matches any pattern in .claudeignore. Uses glob-style matching.
#
# TRIGGER: PreToolUse
# MATCHER: "Read|Edit|Write|Grep|Glob"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Extract file path based on tool type
case "$TOOL" in
  Read|Edit|Write)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    ;;
  Grep|Glob)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)
    ;;
  *) exit 0 ;;
esac

[ -z "$FILE" ] && exit 0

# Find .claudeignore in project root or current directory
IGNORE_FILE=""
for candidate in ".claudeignore" "../.claudeignore" "../../.claudeignore"; do
  if [ -f "$candidate" ]; then
    IGNORE_FILE="$candidate"
    break
  fi
done

[ -z "$IGNORE_FILE" ] && exit 0

# Check each pattern in .claudeignore
while IFS= read -r pattern || [ -n "$pattern" ]; do
  # Skip empty lines and comments
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  # Strip trailing whitespace
  pattern=$(echo "$pattern" | sed 's/[[:space:]]*$//')
  [ -z "$pattern" ] && continue

  # Match: exact path, basename, or glob
  BASENAME=$(basename "$FILE")
  if [[ "$FILE" == $pattern ]] || [[ "$BASENAME" == $pattern ]] || [[ "$FILE" == */$pattern ]]; then
    echo "BLOCKED: File '$FILE' matches .claudeignore pattern '$pattern'." >&2
    echo "This file is excluded from Claude Code access." >&2
    exit 2
  fi
done < "$IGNORE_FILE"

exit 0
