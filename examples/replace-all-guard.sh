#!/bin/bash
# ================================================================
# replace-all-guard.sh — Warn when Edit uses replace_all: true
# ================================================================
# PURPOSE:
#   The Edit tool's replace_all parameter replaces ALL occurrences
#   of old_string in a file. This is extremely dangerous for data
#   files where the same string appears in different contexts
#   (e.g., column names, values, SQL). A single replace_all can
#   corrupt dozens of lines in ways that are hard to detect.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit"
#
# WHY THIS MATTERS:
#   Claude frequently uses replace_all as a shortcut instead of
#   making targeted single-line edits. In code files this is
#   usually safe, but in data/config/SQL files it causes silent
#   corruption — correct values are overwritten along with the
#   intended target.
#
# WHAT IT DOES:
#   Checks if the Edit tool input has replace_all: true. If so,
#   warns via stderr. In strict mode (CC_BLOCK_REPLACE_ALL=1),
#   blocks the operation entirely.
#
# CONFIGURATION:
#   CC_BLOCK_REPLACE_ALL=1 — block replace_all operations (default: warn only)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/41681
# ================================================================

set -u

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-replace-all-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [replace-all-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)

REPLACE_ALL=$(printf '%s' "$INPUT" | jq -r '.tool_input.replace_all // false' 2>/dev/null)

if [ "$REPLACE_ALL" = "true" ]; then
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // "unknown"' 2>/dev/null)
    OLD=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // "" | .[0:60]' 2>/dev/null)

    if [ "${CC_BLOCK_REPLACE_ALL:-0}" = "1" ]; then
        printf 'BLOCKED: replace_all=true on %s\n' "$FILE" >&2
        printf 'Pattern: "%s"\n' "$OLD" >&2
        printf 'replace_all replaces ALL occurrences. Use targeted single edits instead.\n' >&2
        exit 2
    fi

    printf '\n⚠ replace_all=true detected on %s\n' "$FILE" >&2
    printf '  Pattern: "%s"\n' "$OLD" >&2
    printf '  This replaces ALL occurrences. Verify this is intentional.\n\n' >&2
fi

exit 0
