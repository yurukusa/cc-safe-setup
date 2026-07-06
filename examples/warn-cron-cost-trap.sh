#!/bin/bash
# ================================================================
# warn-cron-cost-trap.sh — Warn on cost-trap scheduled tasks
# ================================================================
# PURPOSE:
#   When the model calls CronCreate with a SHORT fire interval AND
#   recurring=true, emit a cost warning. Short-interval recurring
#   schedules are a silent money trap: every fire re-loads the whole
#   conversation as a fresh full turn, so the per-fire cost climbs
#   roughly quadratically with the number of fires in a session.
#
# TRIGGER: PostToolUse
# MATCHER: "CronCreate"
#
# WHY THIS MATTERS:
#   A recurring CronCreate does not run cheaply in the background.
#   Each fire is a complete turn that re-reads the accumulated
#   conversation history, so cost per fire grows as the session
#   grows. A */5 (every 5 min) recurring job left running overnight
#   can fire ~200 times, each one more expensive than the last.
#   Issue #74547 reports ~USD 500 burned by an 11-minute recurring
#   schedule that did nothing but poll an empty directory 88 times
#   in 16 hours. The registration itself is silent — nothing warns
#   the operator that the interval times the growing context equals
#   a quadratic bill.
#
#   This hook is advisory. It never blocks CronCreate; it prints a
#   one-time warning so the operator can widen the interval, set
#   recurring=false, or move the poll to an external scheduler that
#   does not re-load the conversation each fire.
#
# WHAT IT CHECKS:
#   Parses .tool_input.cron and .tool_input.recurring. It derives the
#   smallest gap (in minutes) between consecutive fires from the
#   MINUTE field of the cron expression — the field that actually
#   drives short intervals:
#     *            -> 1 minute   (fires every minute)
#     */N or .../N -> N minutes  (step)
#     a,b,c,...    -> smallest consecutive gap, with 60-wraparound
#     A-B (range)  -> 1 minute (fires every minute within the range)
#     single value -> 60 minutes (fires at most hourly -> safe)
#   Warns only when recurring is true AND the derived interval is
#   below the threshold (default 15 minutes).
#
# DEFENSIVE BEHAVIOR:
#   - Always exits 0 (advisory only, never blocks)
#   - Skips silently if jq is missing
#   - Skips silently if no cron expression is present
#   - Treats an unparseable minute field as safe (no false alarm)
#
# CONFIGURATION (environment variables):
#   CC_CRON_COST_TRAP_DISABLE=1        skip the hook entirely
#   CC_CRON_COST_TRAP_THRESHOLD_MIN=N  interval below N warns (default 15)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/74547  (~USD 500 no-op polling spend)
#
# PAIR WITH:
#   cron-create-receipt.sh   (logs every registration for later audit)
#   daily-cost-guard.sh      (tracks accumulated spend)
#
# TRIGGER: PostToolUse  MATCHER: "CronCreate"
# ================================================================

set -u

# Skip if disabled
if [ "${CC_CRON_COST_TRAP_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Skip if jq is missing — we cannot parse tool_input without it
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

THRESHOLD="${CC_CRON_COST_TRAP_THRESHOLD_MIN:-15}"
# Numeric guard on the threshold
case "$THRESHOLD" in
  ''|*[!0-9]*) THRESHOLD=15 ;;
esac

INPUT=$(cat)

CRON_EXPR=$(printf '%s' "$INPUT" | jq -r '.tool_input.cron // empty' 2>/dev/null)
RECURRING=$(printf '%s' "$INPUT" | jq -r '.tool_input.recurring // false' 2>/dev/null)

# Nothing to do if there is no cron expression
[ -z "$CRON_EXPR" ] && exit 0

# Only recurring schedules have the compounding trap. A one-shot fire
# re-loads the conversation once and stops.
[ "$RECURRING" = "true" ] || exit 0

# Extract the minute field (first whitespace-separated field)
MINUTE=$(printf '%s' "$CRON_EXPR" | awk '{print $1}')
[ -z "$MINUTE" ] && exit 0

# Derive the smallest interval (in minutes) between consecutive fires
# from the minute field alone. This is the practical driver of the trap.
INTERVAL=$(printf '%s' "$MINUTE" | awk '
  {
    f = $0
    # Step form: anything containing "/N" fires every N minutes
    if (f ~ /\//) {
      n = f
      sub(/.*\//, "", n)
      if (n ~ /^[0-9]+$/ && n+0 > 0) { print n+0; next }
    }
    # Every minute
    if (f == "*") { print 1; next }
    # Comma list of explicit minutes: smallest consecutive gap with wraparound
    if (f ~ /,/) {
      n = split(f, parts, ",")
      cnt = 0
      for (i = 1; i <= n; i++) {
        v = parts[i]
        if (v ~ /^[0-9]+$/) { vals[cnt++] = v+0 }
      }
      if (cnt < 2) { print 60; next }
      # simple insertion sort
      for (i = 1; i < cnt; i++) {
        key = vals[i]; j = i - 1
        while (j >= 0 && vals[j] > key) { vals[j+1] = vals[j]; j-- }
        vals[j+1] = key
      }
      mingap = 60
      for (i = 1; i < cnt; i++) {
        gap = vals[i] - vals[i-1]
        if (gap < mingap) mingap = gap
      }
      wrap = (60 - vals[cnt-1]) + vals[0]
      if (wrap < mingap) mingap = wrap
      if (mingap < 1) mingap = 1
      print mingap; next
    }
    # Range without step (e.g. 0-30) fires every minute within the range,
    # so its interval is 1 minute — one of the most expensive forms.
    if (f ~ /^[0-9]+-[0-9]+$/) { print 1; next }
    # Single value -> at most once per hour -> safe
    print 60
  }
')

# Guard: if awk produced nothing numeric, treat as safe
case "$INTERVAL" in
  ''|*[!0-9]*) exit 0 ;;
esac

if [ "$INTERVAL" -lt "$THRESHOLD" ]; then
  cat >&2 <<EOF
[warn-cron-cost-trap] COST TRAP: recurring CronCreate fires about every ${INTERVAL} min.
  cron: "$CRON_EXPR"  recurring: true
  Each fire re-loads the whole conversation as a fresh full turn, so per-fire
  cost grows with the session — the total climbs roughly quadratically with the
  number of fires. Left overnight, a short-interval recurring job can fire
  hundreds of times, each one more expensive than the last (issue #74547 burned
  ~USD 500 polling an empty directory 88 times in 16 hours).
  Fixes: widen the interval (>= ${THRESHOLD} min), set recurring=false for a
  one-shot, or move the poll to an external scheduler that does not re-load the
  conversation each fire.
  Set CC_CRON_COST_TRAP_DISABLE=1 to suppress this warning.
EOF
fi

# Always exit 0 — advisory only, never blocks CronCreate
exit 0
