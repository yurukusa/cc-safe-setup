#!/bin/bash
# agent-sdk-credit-pool-monitor.sh — track `claude -p` usage against the June 15 credit pool cliff
#
# Solves: Anthropic's announcement on 2026-05-13 that, starting 2026-06-15,
#         `claude -p` and Agent SDK usage draws from a separate per-plan monthly
#         credit pool (Pro $20, Max 5x $100, Max 20x $200). Unused credit does
#         not roll over. Operators running heavy programmatic automation under
#         subscription tiers have no visibility into their projected post-cliff
#         cost until they hit the credit ceiling and programmatic usage stops.
#
#         Public references (seven Tier-1 outlets, May 13-14, 2026):
#         - The Register: "Anthropic tosses agents into the API billing pool"
#         - SiliconANGLE: "Anthropic announces programmatic credit pool as agentic tool use rises"
#         - XDA Developers: per-tier credit pool figures + Theo Browne 25x quote
#         - devtoolpicks: per-tier token math + Ben Hylak GPUs quote
#         - latent.space: "Codex Rises, Claude Meters Programmatic Usage"
#         - VentureBeat: third-party agent reinstatement with a catch
#         - PromptZone: cross-customer impact
#         HN threads: 48126281 (parent), 48126438 (companion), 48129813 (Show HN
#         workaround Claude-pee), 48130374 (Tell HN follow-up).
#
# Event:  PreToolUse   Matcher: Bash
# Action: When a Bash tool call invokes `claude -p ...` or `claude --print ...`,
#         append a timestamped entry to ~/.claude/logs/claude-p-calls.log,
#         then compute the running 30-day call count and the projected monthly
#         cost. Emit an advisory message to stderr if the projection exceeds
#         the operator's configured credit pool ceiling.
#
#         Before June 15, the message is a pre-cliff warning ("if this pattern
#         continues, your post-cliff cost will be X"). On or after June 15,
#         the message is a real-time credit-pool drawdown alert.
#
#         The hook never blocks. It is advisory only.
#
# Configuration (environment variables):
#   AGENT_SDK_TIER                   pro | max5x | max20x | team-std | team-prem (default: pro)
#                                    Sets the credit pool ceiling for projection comparison.
#   AGENT_SDK_AVG_CALL_COST          estimated average per-call USD cost (default: 0.05)
#                                    Override if your workload differs from the typical 49,000-token
#                                    Sonnet 4.6 invocation (~$0.05). See Cost Cliff Survival Guide
#                                    Chapter 2 Source 3 for token-level calibration.
#   AGENT_SDK_LOG                    log path (default: ~/.claude/logs/claude-p-calls.log)
#   AGENT_SDK_WARN_THRESHOLD_PCT     projection-vs-ceiling % above which to warn (default: 75)
#   AGENT_SDK_QUIET                  set to 1 to suppress informational messages
#
# Exit codes:
#   0  always (advisory only — never blocks the Bash call)

set -u

INPUT=$(cat 2>/dev/null || true)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Detect `claude -p ...` and `claude --print ...` as whole command words.
# Avoid matching `./my-claude -p` / `someone-claude -p` (hyphen prefix). We
# require `claude` to be at the start or after a shell separator, immediately
# followed (after whitespace) by `-p` or `--print`.
if ! printf '%s' "$CMD" | grep -qE '(^|[;&| 	])claude[ 	]+(-p|--print)(\b|$)'; then
  exit 0
fi

TIER="${AGENT_SDK_TIER:-pro}"
AVG_CALL_COST="${AGENT_SDK_AVG_CALL_COST:-0.05}"
WARN_PCT="${AGENT_SDK_WARN_THRESHOLD_PCT:-75}"
QUIET="${AGENT_SDK_QUIET:-0}"
LOG_PATH="${AGENT_SDK_LOG:-$HOME/.claude/logs/claude-p-calls.log}"

# Tier ceilings, in USD per month. Values per Anthropic announcement 2026-05-13
# (verified via XDA Developers 2026-05-13 and SiliconANGLE 2026-05-14).
case "$TIER" in
  pro)        CEILING=20  ;;
  max5x)      CEILING=100 ;;
  max20x)     CEILING=200 ;;
  team-std)   CEILING=20  ;;
  team-prem)  CEILING=100 ;;
  *)
    {
      echo "agent-sdk-credit-pool-monitor: unknown AGENT_SDK_TIER='$TIER'"
      echo "  Expected one of: pro / max5x / max20x / team-std / team-prem"
      echo "  Defaulting to 'pro' (\$20/month ceiling). Set AGENT_SDK_TIER to silence."
    } >&2
    CEILING=20
    ;;
esac

# Ensure log directory exists.
mkdir -p "$(dirname "$LOG_PATH")" 2>/dev/null

# Append a timestamped entry (epoch seconds + cmd length).
NOW=$(date +%s 2>/dev/null || echo 0)
CMD_LEN=$(printf '%s' "$CMD" | wc -c | tr -d ' ')
printf '%s\t%s\n' "$NOW" "$CMD_LEN" >> "$LOG_PATH" 2>/dev/null

# Count entries within the last 30 days (2,592,000 seconds).
WINDOW_START=$((NOW - 2592000))
[ "$WINDOW_START" -lt 0 ] && WINDOW_START=0

COUNT=$(awk -F'\t' -v cutoff="$WINDOW_START" '$1 >= cutoff { c++ } END { print c+0 }' "$LOG_PATH" 2>/dev/null)
[ -z "$COUNT" ] && COUNT=0

# Project monthly cost at AVG_CALL_COST per call.
PROJECTED=$(awk -v c="$COUNT" -v r="$AVG_CALL_COST" 'BEGIN { printf "%.2f", c * r }')

# Compare projection to ceiling.
PCT=$(awk -v p="$PROJECTED" -v ceil="$CEILING" 'BEGIN { printf "%.0f", (ceil > 0 ? p / ceil * 100 : 0) }')

# Determine cliff window. Hard date 2026-06-15 00:00 UTC = 1781308800
CLIFF_TS=1781308800
PRE_CLIFF=$([ "$NOW" -lt "$CLIFF_TS" ] && echo 1 || echo 0)

BANNER='ⓘ agent-sdk-credit-pool-monitor (June 15, 2026 cliff)'

if [ "$PCT" -ge "$WARN_PCT" ]; then
  {
    echo "$BANNER"
    echo "  30-day \`claude -p\` calls: $COUNT (projected: \$$PROJECTED / month)"
    echo "  Tier '$TIER' ceiling: \$$CEILING — your projection is ${PCT}% of ceiling."
    if [ "$PRE_CLIFF" = "1" ]; then
      echo "  Pre-cliff: this projection becomes your effective programmatic budget"
      echo "  on 2026-06-15. Above-ceiling usage will charge at full API rates."
    else
      echo "  Post-cliff: \$$PROJECTED already approaches the \$$CEILING credit pool."
      echo "  Above-ceiling usage charges at full API rates; non-rollover monthly."
    fi
    echo "  Response paths (Migration Playbook Edition 2, Chapter 8 decision tree):"
    echo "    - Path A: stay; restructure for cache hit ratio"
    echo "    - Path B': model-only swap (e.g., Z.AI GLM Coding Plan)"
    echo "    - Path D: hybrid delegation (e.g., Kimi K2.5 as side-worker)"
    echo "    - Path C: full DIY stack (3x ceiling threshold)"
    echo "  Calibrate AVG_CALL_COST per Cost Cliff Survival Guide Chapter 2."
  } >&2
elif [ "$QUIET" != "1" ]; then
  {
    echo "$BANNER (info)"
    echo "  30-day \`claude -p\` calls: $COUNT (projected: \$$PROJECTED / month)"
    echo "  Tier '$TIER' ceiling: \$$CEILING (${PCT}% used)."
  } >&2
fi

exit 0
