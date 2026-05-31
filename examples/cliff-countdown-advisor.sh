#!/bin/bash
# cliff-countdown-advisor.sh
#
# SessionStart hook that articulates the days remaining until the 2026-06-15
# Anthropic billing-split cliff, plus operator-side guidance to minimize Pool 2
# usage signals during the preparation window.
#
# Designed to surface the cliff timing once per session without becoming noise:
# - Quiet beyond 30 days before cliff (no output)
# - Caution between 15-30 days before cliff (single-line note)
# - Elevated between 1-14 days before cliff (multi-line advisory)
# - Acute on cliff day (2026-06-15, dedicated message)
# - Post-cliff window (1-30 days after) surfaces the diff-capture procedure
# - Silent beyond 30 days after cliff
#
# Environment variables (all optional):
# - CC_CLIFF_DATE: override the cliff date (YYYY-MM-DD format, default 2026-06-15)
# - CC_CLIFF_QUIET: if set to "1", suppress all output (opt-out)
# - CC_CLIFF_DISABLE: if set to "1", disable the hook entirely (alias for QUIET)
#
# Exit codes:
# - Always exits 0 (advisory hook, never blocks)
#
# Reference: docs/june-15-cliff-14-day-plan.md (the 14-day preparation plan)

set -uo pipefail

# Opt-out check
if [[ "${CC_CLIFF_QUIET:-0}" == "1" ]] || [[ "${CC_CLIFF_DISABLE:-0}" == "1" ]]; then
  exit 0
fi

CLIFF_DATE="${CC_CLIFF_DATE:-2026-06-15}"

# Convert dates to seconds since epoch for comparison
if ! cliff_epoch=$(date -d "${CLIFF_DATE}" +%s 2>/dev/null); then
  # Date parsing failed (e.g. on macOS without GNU date) — silently exit
  exit 0
fi

now_epoch=$(date +%s)
diff_seconds=$((cliff_epoch - now_epoch))
diff_days=$((diff_seconds / 86400))

# Today is 2026-06-15 (cliff day, +/- 12 hours)
if [[ ${diff_days} -ge -1 ]] && [[ ${diff_days} -le 0 ]]; then
  cat <<'EOF'
[cliff-countdown] ★ 2026-06-15 cliff day. Anthropic billing split is active now.

Today's measurement priority:
1. Capture Anthropic Console Usage snapshot before any heavy work
2. Watch for the first Pool 2 charges to surface (typically within 12-24h)
3. Save the snapshot to ~/ops/measurements/2026-06-15-cliff-day.json

Reference (free, MIT):
- 14-day plan: docs/june-15-cliff-14-day-plan.md (post-cliff diff section)
- cliff-survival book free preview: https://zenn.dev/yurukusa/books/june-15-cliff-survival

Set CC_CLIFF_QUIET=1 to suppress this advisory.
EOF
  exit 0
fi

# 1-14 days before cliff (elevated advisory)
if [[ ${diff_days} -ge 1 ]] && [[ ${diff_days} -le 14 ]]; then
  cat <<EOF
[cliff-countdown] ⚠ ${diff_days} days until the 2026-06-15 cliff.

Operator-side actions to consider:
- Capture Anthropic Console Usage baseline (Pool 1 vs Pool 2 ratio)
- Reduce \`claude -p\` and Agent SDK calls running on cron / background paths
- Stop parallel \`claude -p\` invocations (run sequentially during the window)
- Set or verify the monthly Spend Limit in Anthropic Console

Reference (free, MIT):
- 14-day plan: docs/june-15-cliff-14-day-plan.md
- cliff-survival book (¥800): https://zenn.dev/yurukusa/books/june-15-cliff-survival

Set CC_CLIFF_QUIET=1 to suppress this advisory.
EOF
  exit 0
fi

# 15-30 days before cliff (caution)
if [[ ${diff_days} -ge 15 ]] && [[ ${diff_days} -le 30 ]]; then
  echo "[cliff-countdown] ${diff_days} days until the 2026-06-15 billing cliff. Start the baseline capture this week. Reference: docs/june-15-cliff-14-day-plan.md"
  exit 0
fi

# 1-30 days after cliff (post-cliff diff capture)
if [[ ${diff_days} -le -2 ]] && [[ ${diff_days} -ge -30 ]]; then
  days_after=$((-diff_days))
  echo "[cliff-countdown] Day ${days_after} after the 2026-06-15 cliff. Capture diff vs pre-cliff baseline if not already done. Reference: docs/june-15-cliff-14-day-plan.md (6/16 onward section)."
  exit 0
fi

# Otherwise quiet
exit 0
