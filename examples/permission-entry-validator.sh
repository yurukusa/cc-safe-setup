#!/bin/bash
# permission-entry-validator.sh — Clean broken permission entries from settings
#
# Solves: Shell redirect targets saved as standalone permissions (#40382).
#         Commands like `az ... > "filepath"` cause Claude Code to save
#         `Bash("D:/path/file.json")` which is a bare filepath, not a command.
#
# How it works: Stop hook that reads settings.local.json and removes
#   permission entries that are bare file paths (not valid command patterns).
#   Identifies entries matching path patterns without a command prefix.
#
# TRIGGER: Stop
# MATCHER: ""

set -euo pipefail

SETTINGS_FILE=".claude/settings.local.json"
[ -f "$SETTINGS_FILE" ] || exit 0

# Check for broken entries (bare file paths as Bash permissions)
BROKEN=$(jq -r '
  .permissions.allow // [] | .[] |
  select(
    startswith("Bash(\"") and
    (
      # Windows paths
      test("^Bash\\(\"[A-Z]:/") or
      # Unix absolute paths without command
      test("^Bash\\(\"/[^\"]*\"\\)$")
    ) and
    # Must NOT contain a space (command + args have spaces)
    (test("^Bash\\(\"[^\" ]*\"\\)$"))
  )
' "$SETTINGS_FILE" 2>/dev/null || true)

if [ -n "$BROKEN" ]; then
    COUNT=$(echo "$BROKEN" | wc -l)
    echo "WARNING: Found $COUNT broken permission entries (bare file paths):" >&2
    echo "$BROKEN" | head -5 | while IFS= read -r entry; do
        echo "  $entry" >&2
    done
    echo "" >&2
    echo "These entries were likely created by 'Always allow' on commands with" >&2
    echo "shell redirects (> filepath). They don't match any command pattern." >&2
    echo "Consider removing them from $SETTINGS_FILE" >&2
fi

exit 0
