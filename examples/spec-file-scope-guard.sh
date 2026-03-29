#!/bin/bash
# spec-file-scope-guard.sh — Restrict edits to files mentioned in a spec document
#
# Solves: Agent ignoring specification across multiple sessions (#40383).
#         Claude modifies files not mentioned in the spec, introduces
#         fabricated data, and drifts from the stated objective.
#
# How it works: Reads a spec/requirements file, extracts file paths and
#   directory names mentioned in it, then blocks Edit/Write to files
#   outside that scope.
#
# Setup:
#   echo "spec.md" > .claude/spec-file.txt
#   # Or set CC_SPEC_FILE=spec.md
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Find spec file
SPEC_FILE="${CC_SPEC_FILE:-}"
if [ -z "$SPEC_FILE" ] && [ -f ".claude/spec-file.txt" ]; then
    SPEC_FILE=$(head -1 ".claude/spec-file.txt" | tr -d '\n')
fi
[ -z "$SPEC_FILE" ] && exit 0
[ -f "$SPEC_FILE" ] || exit 0

# Extract paths/directories mentioned in spec
# Matches: path/to/file.ext, src/components/, ./config.ts, etc.
MENTIONED=$(grep -oE '(\.?/?[a-zA-Z0-9_-]+/)+[a-zA-Z0-9_.-]*' "$SPEC_FILE" | sort -u || true)

if [ -z "$MENTIONED" ]; then
    # No paths found in spec — don't restrict
    exit 0
fi

# Check if the target file matches any mentioned path
BASENAME=$(basename "$FILE")
DIRNAME=$(dirname "$FILE")

for path in $MENTIONED; do
    # Match if file path contains the spec path
    if echo "$FILE" | grep -qF "$path"; then
        exit 0
    fi
    # Match if basename matches
    if echo "$BASENAME" | grep -qF "$path"; then
        exit 0
    fi
done

echo "WARNING: Editing file not mentioned in spec ($SPEC_FILE):" >&2
echo "  File: $FILE" >&2
echo "  Spec mentions: $(echo "$MENTIONED" | head -5 | tr '\n' ', ')" >&2
echo "  Stay focused on the specification." >&2
# Warning only — change to exit 2 to block
exit 0
