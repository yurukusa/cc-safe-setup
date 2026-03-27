#!/bin/bash
# github-actions-guard.sh — Validate GitHub Actions workflow changes
#
# Prevents: Broken CI/CD pipelines from workflow syntax errors.
#           Claude sometimes generates invalid workflow YAML.
#
# Checks:
#   - Workflow must have 'on' trigger
#   - Job names must exist
#   - 'uses' actions should have version pins
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check GitHub Actions workflow files
echo "$FILE" | grep -qE '\.github/workflows/.*\.ya?ml$' || exit 0
[ ! -f "$FILE" ] && exit 0

WARNINGS=""

# Check for 'on' trigger
if ! grep -qE '^on:' "$FILE"; then
  WARNINGS="${WARNINGS}\n  Missing 'on:' trigger definition"
fi

# Check for unpinned actions (uses: without @sha or @v)
UNPINNED=$(grep -E '^\s*uses:\s+\S+' "$FILE" | grep -v '@' | head -3)
if [ -n "$UNPINNED" ]; then
  WARNINGS="${WARNINGS}\n  Unpinned action versions (use @v or @sha):"
  echo "$UNPINNED" | while read -r line; do
    WARNINGS="${WARNINGS}\n    $line"
  done
fi

# Check for 'runs-on' in jobs
if grep -qE '^\s+jobs:' "$FILE" && ! grep -qE 'runs-on:' "$FILE"; then
  WARNINGS="${WARNINGS}\n  Jobs missing 'runs-on' runner specification"
fi

if [ -n "$WARNINGS" ]; then
  echo "GitHub Actions warnings in $FILE:" >&2
  echo -e "$WARNINGS" >&2
fi

exit 0
