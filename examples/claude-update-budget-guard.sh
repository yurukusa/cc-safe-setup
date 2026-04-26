#!/bin/bash
# claude-update-budget-guard.sh — warn/block `claude update` when 5h quota is tight
#
# Solves: #52890 (opened 2026-04-24, v2.1.98, platform:macos, labels area:cost).
#         A single `claude update` invocation consumed ~7% of the 5-hour budget
#         and ~3% of the weekly budget on a Max 20x plan — silently. The burn
#         compounds with Marketplace 404s and 429 retry storms that the user
#         sees in their logs. Anthropic has not commented on the issue at the
#         time this hook was written.
#
# Event: PreToolUse   Matcher: Bash
# Action: When a Bash tool call invokes `claude update` / `claude self-update`,
#         read the remaining 5-hour quota from `claude /usage --json`
#         (Claude Code >= 2.1.118). If the remaining percentage is below
#         CLAUDE_UPDATE_BUDGET_THRESHOLD (default 30), either warn (default)
#         or block (exit 2) — depending on CLAUDE_UPDATE_BUDGET_MODE.
#         If `/usage --json` is unavailable (earlier version or error), emit
#         a version-agnostic warning and fall through.
#
# Configuration:
#   CLAUDE_UPDATE_BUDGET_THRESHOLD  percent (default 30). Below this, take action.
#   CLAUDE_UPDATE_BUDGET_MODE       warn | block (default warn — never breaks CC)
#   CLAUDE_UPDATE_USAGE_CMD         override probe command (for tests)
#
# Exit codes:
#   0  allow (with warning printed to stderr if threshold crossed)
#   2  block (only when MODE=block and threshold crossed)

set -u

INPUT=$(cat 2>/dev/null || true)

# Non-Bash tools: nothing to do.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Detect `claude update` / `claude self-update`. Require `claude` as a
# whole command word so `./claude-update-smart.sh` / `my-claude update` / a
# commit message mentioning "claude update" don't trigger us.
if ! printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])claude([[:space:]]+[^;&|]*)?[[:space:]]+(update|self-update)(\b|$)'; then
  exit 0
fi

THRESHOLD="${CLAUDE_UPDATE_BUDGET_THRESHOLD:-30}"
MODE="${CLAUDE_UPDATE_BUDGET_MODE:-warn}"
PROBE="${CLAUDE_UPDATE_USAGE_CMD:-claude /usage --json}"

# Probe remaining quota. Older CC versions (<=2.1.117) do not ship `/usage`;
# any non-zero exit or non-JSON output means "unknown — warn and continue".
USAGE_JSON=$(eval "$PROBE" 2>/dev/null || true)
REMAINING_PCT=""
if [ -n "$USAGE_JSON" ]; then
  # Accept several plausible shapes from /usage --json. Real field names may
  # shift across CC releases; we try the common ones and stop at the first hit.
  for path in \
    '.five_hour.remaining_percent' \
    '.fiveHour.remainingPercent' \
    '.sessions."5h".remaining_percent' \
    '.quota.fiveHour.percent_remaining' \
    '.limits."5h".percent_remaining'; do
    val=$(printf '%s' "$USAGE_JSON" | jq -r "$path // empty" 2>/dev/null)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
      REMAINING_PCT="$val"
      break
    fi
  done
fi

BANNER='⚠ claude-update-budget-guard: Issue #52890'
REF='https://github.com/anthropics/claude-code/issues/52890'

if [ -z "$REMAINING_PCT" ]; then
  {
    echo "$BANNER"
    echo "  Cannot read /usage --json (Claude Code < 2.1.118 or probe failed)."
    echo "  \`claude update\` has been reported to burn ~7% of the 5h budget"
    echo "  on a single invocation. Consider running the command from a"
    echo "  separate shell rather than from inside an active CC session."
    echo "  Ref: $REF"
  } >&2
  exit 0
fi

# Compare with threshold using awk (handles floats).
CROSSED=$(awk -v r="$REMAINING_PCT" -v t="$THRESHOLD" 'BEGIN { print (r+0 < t+0) ? 1 : 0 }')

if [ "$CROSSED" = "1" ]; then
  {
    echo "$BANNER"
    echo "  5-hour quota remaining: ${REMAINING_PCT}% (threshold: ${THRESHOLD}%)."
    echo "  \`claude update\` can consume ~7% of the 5h budget in one call."
    echo "  Running it now may trigger your hard quota limit."
    echo "  Suggested: skip until the next 5h reset, or run from outside CC."
    echo "  Ref: $REF"
  } >&2
  if [ "$MODE" = "block" ]; then
    exit 2
  fi
  exit 0
fi

# Quota OK — still post an informational note so the user sees the cost.
{
  echo "$BANNER (info)"
  echo "  5h quota remaining: ${REMAINING_PCT}% — above threshold."
  echo "  Note: this single update is expected to burn ~7% of your 5h budget."
} >&2
exit 0
