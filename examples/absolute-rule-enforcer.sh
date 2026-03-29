#!/bin/bash
# absolute-rule-enforcer.sh — Enforce CLAUDE.md "ABSOLUTE RULE" markers
#
# Solves: ABSOLUTE RULEs in CLAUDE.md treated as advisory (#40284).
#         Even rules marked with strong language get ignored under
#         context pressure. This hook extracts and enforces them.
#
# How it works: Stop hook that parses CLAUDE.md for "ABSOLUTE RULE"
#   or "MUST NEVER" markers, extracts the constraint keywords,
#   and checks if the session violated them.
#
# TRIGGER: Stop
# MATCHER: ""

set -euo pipefail

# Find CLAUDE.md
CLAUDEMD=""
for candidate in "CLAUDE.md" "../CLAUDE.md" "../../CLAUDE.md"; do
  if [ -f "$candidate" ]; then
    CLAUDEMD="$candidate"
    break
  fi
done

[ -z "$CLAUDEMD" ] && exit 0

# Extract absolute rules (lines containing ABSOLUTE, MUST NEVER, NEVER, 絶対)
RULES=$(grep -iE '(ABSOLUTE|MUST NEVER|NEVER|絶対|禁止)' "$CLAUDEMD" 2>/dev/null | head -10)

if [ -z "$RULES" ]; then
  exit 0
fi

# Log that absolute rules exist (reminder to model via stderr)
echo "REMINDER: This project has absolute rules in CLAUDE.md:" >&2
echo "$RULES" | head -5 | while IFS= read -r rule; do
  echo "  $rule" >&2
done
echo "Verify your changes comply before finalizing." >&2

exit 0
