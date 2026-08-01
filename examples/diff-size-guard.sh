#!/bin/bash
# ================================================================
# diff-size-guard.sh — Warn on large uncommitted changes
# ================================================================
# PURPOSE:
#   Claude Code can modify dozens of files in a single session
#   without committing. By the time you notice, the diff is
#   unmanageable. This hook warns when the working tree has
#   too many changed files.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHEN IT FIRES:
#   On git commit — checks if the commit is too large
#   Configurable thresholds via environment variables
#
# CONFIGURATION:
#   CC_DIFF_WARN=10    — warn when staging 10+ files (default)
#   CC_DIFF_BLOCK=50   — block when staging 50+ files (default)
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-diff-size-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [diff-size-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only check git commit and git add
if ! echo "$COMMAND" | grep -qE '^\s*git\s+(commit|add\s+(-A|--all|\.))'; then
    exit 0
fi

# Check number of changed files
if ! command -v git &>/dev/null || ! [ -d .git ]; then
    exit 0
fi

WARN="${CC_DIFF_WARN:-10}"
BLOCK="${CC_DIFF_BLOCK:-50}"

# Count staged + unstaged changed files
CHANGED=$(git diff --name-only HEAD 2>/dev/null | wc -l)
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
TOTAL=$((CHANGED + STAGED))

if [ "$TOTAL" -ge "$BLOCK" ]; then
    echo "BLOCKED: $TOTAL files changed — too large for one commit." >&2
    echo "" >&2
    echo "Break this into smaller, reviewable commits:" >&2
    echo "  git add src/feature/ && git commit -m 'feat: add feature'" >&2
    echo "  git add tests/ && git commit -m 'test: add feature tests'" >&2
    echo "" >&2
    echo "Set CC_DIFF_BLOCK to adjust the limit (current: $BLOCK)." >&2
    exit 2
elif [ "$TOTAL" -ge "$WARN" ]; then
    echo "WARNING: $TOTAL files changed. Consider splitting into smaller commits." >&2
fi

exit 0
