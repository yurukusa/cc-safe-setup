#!/bin/bash
# session-start-quota-status.sh — Compute a real-time approximation of the
# operator's recent token usage from local JSONL transcripts and surface it
# to Claude Code at session start, so the operator sees their quota
# posture before issuing the first prompt.
#
# Addresses the cluster of issues for which Anthropic does not provide a
# native dashboard:
#
#   #16157 (1470+ comments) — "Instantly hitting usage limits with Max
#                              subscription"
#   #38335 (723+ comments)  — "Claude Max plan session limits exhausted
#                              abnormally fast"
#   #29579 (150+ comments)  — "Rate limit reached despite Claude Max
#                              subscription and only 16% usage"
#
# The web-search summary from 2026-05 named the gap explicitly:
#   "There's no official dashboard that shows weekly-cap status in real
#    time, and this gap is one of the most recurring complaints from
#    power users in Anthropic forums."
#
# This hook is the operator-side stopgap. It reads
# `~/.claude/projects/*/[session-id].jsonl` files modified in the last
# 5 hours (rolling-window approximation of the Anthropic 5-hour cap)
# and the last 7 days (rolling-window approximation of the weekly cap),
# sums the input/output/cache tokens by model, computes an estimated
# dollar-cost at standard API rates, and emits a <system-reminder>
# surfacing the totals.
#
# Important caveats — read these before relying on the numbers:
#
# 1. Anthropic's real cap is not directly observable from local
#    transcripts. The hook uses a rolling-window approximation that
#    correlates with cap consumption but does not equal it.
# 2. Subscription quota is consumed at SUBSCRIPTION rates, not API
#    rates. The dollar figures the hook emits are the EQUIVALENT API
#    cost — useful for comparing against the subscription credit pool
#    (especially the June-15-and-after Pool 2 credit) but not directly
#    equal to what the subscription "spent" against the quota.
# 3. The 5-hour window calculation is wall-clock-based on file mtime,
#    not based on Anthropic's actual reset timing.
# 4. The hook is non-blocking. It surfaces information; it does not
#    refuse the session.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# CONFIGURATION (environment variables):
#   CC_QUOTA_5H_WARN_USD       default 5.0 — emit a warning if 5-hour
#                                            equivalent-API-cost exceeds this
#   CC_QUOTA_WEEKLY_WARN_USD   default 50.0 — same for weekly
#   CC_QUOTA_PROJECTS_DIR      default ~/.claude/projects — JSONL roots
#   CC_QUOTA_STATUS_DISABLE    set "1" to disable the hook entirely
#
# USAGE (settings.json):
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "",
#         "hooks": [{
#           "type": "command",
#           "command": "~/.claude/hooks/session-start-quota-status.sh"
#         }]
#       }]
#     }
#   }

set -uo pipefail

[ "${CC_QUOTA_STATUS_DISABLE:-0}" = "1" ] && exit 0

PROJECTS_DIR="${CC_QUOTA_PROJECTS_DIR:-$HOME/.claude/projects}"
WARN_5H="${CC_QUOTA_5H_WARN_USD:-5.0}"
WARN_WEEKLY="${CC_QUOTA_WEEKLY_WARN_USD:-50.0}"

[ ! -d "$PROJECTS_DIR" ] && exit 0  # No projects directory → silent no-op.

# Need jq for JSONL parsing; awk for aggregation.
command -v jq >/dev/null 2>&1 || exit 0

# Compute the rolling sums for one window in minutes.
# Returns lines: "model:input:output:cache_read:cache_write:dollars"
compute_window() {
    local window_minutes="$1"
    local out

    out=$(find "$PROJECTS_DIR" -name '*.jsonl' -mmin "-$window_minutes" 2>/dev/null -exec \
        jq -r 'select(.message.usage and .message.model) | "\(.message.model)\t\(.message.usage.input_tokens // 0)\t\(.message.usage.output_tokens // 0)\t\(.message.usage.cache_read_input_tokens // 0)\t\(.message.usage.cache_creation_input_tokens // 0)"' {} \; 2>/dev/null \
        | awk -F'\t' '
            {
                model = $1
                # Bucket model family for rate lookup
                if (model ~ /opus/) family = "opus"
                else if (model ~ /sonnet/) family = "sonnet"
                else if (model ~ /haiku/) family = "haiku"
                else family = "other"

                i[family] += $2
                o[family] += $3
                cr[family] += $4
                cw[family] += $5
            }
            END {
                # API rates per million tokens (2026 standard pricing).
                # cache_read is typically 10% of input rate;
                # cache_creation is typically 25% above input rate (1.25x).
                # Using simple input/output rates here for the dollar
                # estimate; cache costs are a refinement.
                rates_in["opus"] = 15.0;   rates_out["opus"] = 75.0
                rates_in["sonnet"] = 3.0;  rates_out["sonnet"] = 15.0
                rates_in["haiku"] = 1.0;   rates_out["haiku"] = 5.0
                rates_in["other"] = 3.0;   rates_out["other"] = 15.0

                for (f in i) {
                    # Cost includes cache_read (at 10% of input rate, an
                    # approximation) and cache_write (at 1.25x input).
                    cost = (i[f] + cw[f] * 1.25 + cr[f] * 0.1) * rates_in[f] / 1000000.0 \
                         + o[f] * rates_out[f] / 1000000.0
                    printf "%s\t%d\t%d\t%d\t%d\t%.4f\n", f, i[f], o[f], cr[f], cw[f], cost
                }
            }
        ')
    echo "$out"
}

# 5-hour window (in minutes)
WINDOW_5H=300
# 7-day window (in minutes)
WINDOW_WEEKLY=10080

DATA_5H=$(compute_window "$WINDOW_5H")
DATA_WEEKLY=$(compute_window "$WINDOW_WEEKLY")

# If both empty, no recent activity — exit silently.
[ -z "$DATA_5H" ] && [ -z "$DATA_WEEKLY" ] && exit 0

# Compute totals.
total_5h_cost=$(echo "$DATA_5H" | awk -F'\t' '{s += $6} END {printf "%.2f", s+0}')
total_weekly_cost=$(echo "$DATA_WEEKLY" | awk -F'\t' '{s += $6} END {printf "%.2f", s+0}')

# Format the per-family breakdown.
format_data() {
    local data="$1"
    [ -z "$data" ] && { echo "  (no activity in this window)"; return; }
    echo "$data" | awk -F'\t' '
        {
            family = $1
            i = $2; o = $3; cr = $4; cw = $5; cost = $6
            tot_tokens = i + o + cr + cw
            printf "  %-7s input %s  output %s  cache_read %s  cache_write %s  est_cost $%.2f\n",
                family, fmt(i), fmt(o), fmt(cr), fmt(cw), cost
        }
        function fmt(n) {
            if (n >= 1000000) return sprintf("%.1fM", n/1000000)
            else if (n >= 1000) return sprintf("%.1fk", n/1000)
            else return sprintf("%d", n)
        }
    '
}

# Determine warning level.
warn_5h=""
warn_weekly=""
if awk -v c="$total_5h_cost" -v t="$WARN_5H" 'BEGIN {exit !(c+0 >= t+0)}'; then
    warn_5h=" [WARN: above CC_QUOTA_5H_WARN_USD threshold of \$$WARN_5H]"
fi
if awk -v c="$total_weekly_cost" -v t="$WARN_WEEKLY" 'BEGIN {exit !(c+0 >= t+0)}'; then
    warn_weekly=" [WARN: above CC_QUOTA_WEEKLY_WARN_USD threshold of \$$WARN_WEEKLY]"
fi

# Emit on stderr (SessionStart non-blocking convention).
cat >&2 <<EOF
<system-reminder>
QUOTA STATUS (estimated from local JSONL transcripts; not Anthropic-authoritative)

Last 5 hours — estimated API-equivalent cost: \$${total_5h_cost}${warn_5h}
$(format_data "$DATA_5H")

Last 7 days — estimated API-equivalent cost: \$${total_weekly_cost}${warn_weekly}
$(format_data "$DATA_WEEKLY")

Notes:
- These figures are the equivalent-API cost of your recent token consumption.
  Compare against your subscription tier's Pool 2 credit (June 15 onward:
  \$20 Pro / \$100 Max 5x / \$200 Max 20x per month for programmatic usage).
- The dashboard Anthropic does not yet provide (#16157, #38335, #29579) lives
  here in the meantime. Set CC_QUOTA_STATUS_DISABLE=1 to silence.
- Cache cost approximation: cache_read at 10% of input rate, cache_write at
  1.25x input rate. Refine via CC_QUOTA_* env vars if needed.
</system-reminder>
EOF

exit 0
