#!/bin/bash
# claudemd-violation-detector.sh — Remind critical CLAUDE.md rules after tool use
#
# Solves: Claude ignores CLAUDE.md instructions, especially after
#         context compaction or in long sessions (#40930).
#
# How it works: After each tool use, extracts and prints
#   critical rules (ABSOLUTE/MUST NEVER/NEVER/禁止) from CLAUDE.md
#   as a reminder. Runs every N tool calls to avoid noise.
#
# TRIGGER: PostToolUse
# MATCHER: ""

set -euo pipefail

# Rate limit: only remind every 20 tool calls
COUNTER_FILE="/tmp/claudemd-reminder-counter"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
[ $((COUNT % 20)) -ne 0 ] && exit 0

# Find CLAUDE.md
CLAUDEMD=""
for candidate in "CLAUDE.md" ".claude/CLAUDE.md" "../CLAUDE.md"; do
  [ -f "$candidate" ] && CLAUDEMD="$candidate" && break
done
[ -z "$CLAUDEMD" ] && exit 0

# Extract critical rules
RULES=$(grep -iE '(ABSOLUTE|MUST NEVER|NEVER DO|禁止|絶対)' "$CLAUDEMD" 2>/dev/null | head -5 || true)
[ -z "$RULES" ] && exit 0

echo "📋 CLAUDE.md critical rules reminder:" >&2
echo "$RULES" >&2
exit 0
