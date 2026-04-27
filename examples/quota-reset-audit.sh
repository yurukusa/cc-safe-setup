#!/bin/bash
# quota-reset-audit.sh — weekly quota reset cluster logger (Incident 9)
# Why: On 2026-04-23 users reported /usage showing quota available while
#      sessions were being rate-limited. Client-side vs server-side
#      timezone handling of the weekly reset diverged. The dashboard's
#      resets_at value is the only ground truth available to users, and
#      a log of resets_at at each session start is the only way to prove
#      "the dashboard said X, the actual reset happened Y."
# Event: SessionStart
# Action: Capture /usage --json at session start. Log the timestamp,
#         resets_at, and percent-used to ~/.claude/logs/usage-audit.log.
#         If /usage is unavailable (pre-v2.1.118) log a placeholder so the
#         session never fails because of the hook.

set -u

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/usage-audit.log"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

fetch_usage() {
  # Prefer the claude CLI subcommand when available (v2.1.118+ shipped
  # /usage with --json output). Fall back to `claude usage --json` which
  # some earlier builds exposed. If neither works, return empty.
  local out=""
  if command -v claude >/dev/null 2>&1; then
    out=$(timeout 5 claude /usage --json 2>/dev/null || true)
    if [ -z "$out" ] || ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      out=$(timeout 5 claude usage --json 2>/dev/null || true)
    fi
  fi
  printf '%s' "$out"
}

USAGE_JSON=$(fetch_usage)

if [ -z "$USAGE_JSON" ] || ! printf '%s' "$USAGE_JSON" | jq -e . >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$TS" "$SESSION_ID" "unavailable" "unavailable" "unavailable" \
    >> "$LOG_FILE"
  exit 0
fi

# Expected /usage fields vary by CC version. Pull common ones defensively.
RESETS_AT=$(printf '%s' "$USAGE_JSON" | jq -r '.weekly.resets_at // .resets_at // .weeklyResetsAt // "unknown"' 2>/dev/null)
PCT_USED=$(printf '%s' "$USAGE_JSON" | jq -r '.weekly.percent_used // .percent_used // .weeklyPercentUsed // "unknown"' 2>/dev/null)
TIER=$(printf '%s' "$USAGE_JSON" | jq -r '.tier // .plan // "unknown"' 2>/dev/null)

printf '%s\t%s\t%s\t%s\t%s\n' \
  "$TS" "$SESSION_ID" "$TIER" "$RESETS_AT" "$PCT_USED" \
  >> "$LOG_FILE"

exit 0
