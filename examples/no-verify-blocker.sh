#!/bin/bash
# ================================================================
# no-verify-blocker.sh — Block --no-verify on git commands
# ================================================================
# PURPOSE:
#   Claude Code may use --no-verify to skip pre-commit hooks,
#   bypassing safety checks like linting, tests, and secret scanning.
#   This hook blocks all --no-verify usage unless explicitly allowed.
#
#   Solves: #40117 — Agent used --no-verify on 6 consecutive commits,
#   silently bypassing pre-commit hooks that validate tests, secrets,
#   and production readiness.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-verify-blocker-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-verify-blocker]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Block --no-verify on any git command
if echo "$COMMAND" | grep -qE '\bgit\b.*--no-verify'; then
    echo "BLOCKED: --no-verify bypasses git hooks (pre-commit, pre-push)" >&2
    echo "Fix the underlying issue instead of skipping hooks" >&2
    exit 2
fi

# Also block the short form -n for git commit (which means --no-verify)
if echo "$COMMAND" | grep -qE '\bgit\s+commit\b.*\s-[a-zA-Z]*n'; then
    # Avoid false positive: -n alone is not always --no-verify
    # Only block if it looks like a commit with -n flag
    if echo "$COMMAND" | grep -qE '\bgit\s+commit\s+-n\b'; then
        echo "BLOCKED: git commit -n skips pre-commit hook" >&2
        exit 2
    fi
fi

exit 0
