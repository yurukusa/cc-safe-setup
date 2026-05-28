#!/bin/bash
# ================================================================
# compact-dispatch-watchdog.sh — Warn when context usage crosses
#   a configurable threshold without a recent compact_boundary
#   event in the transcript, i.e. when auto-compact dispatch has
#   gone silent on the new prompt-cache-prefix code path.
# ================================================================
# PURPOSE:
#   Issue #63015 documents that on Claude Code v2.1.153 with Max
#   subscription in 200K mode, the client's own statusline reports
#   "100% context used" but auto-compact never fires — no
#   `compact_boundary` events appear in the transcript across the
#   entire session, despite the threshold being signalled on
#   screen. The reporter traced the suspect to a GrowthBook A/B
#   flag (`tengu_compact_cache_prefix`) gating a new compaction
#   implementation whose dispatch path can fail silently.
#
#   The earlier `auto-compact-context-monitor.sh` detects *when*
#   auto-compaction *did* happen by watching context size drops.
#   It cannot see the inverse case — context that should have
#   compacted but didn't. This Stop hook covers that gap.
#
#   The hook is operator-side and observational. The dispatch
#   path itself is not reachable from `settings.json` overrides
#   or any other operator surface (Cluster 10 in the cc-safe-setup
#   tracker — server-pushed GrowthBook flags rewrite client state).
#   Recovery on a hit is a manual `/compact` from the operator.
#
# TRIGGER: Stop  MATCHER: ""
# CLUSTER: 10 (GrowthBook A/B flag client-side overrides)
#
# BEHAVIOR:
#   - Read transcript_path from Stop hook input.
#   - Extract the most recent message.usage block to compute
#     current total input tokens (input + cache_read +
#     cache_creation) and a ratio against a 200K window
#     (configurable for 1M mode).
#   - Count `compact_boundary` events in the transcript. The
#     event marker is the substring `compact_boundary` written
#     by the Claude Code runtime when a compaction lands.
#   - If usage ratio crosses the warn threshold AND no
#     compact_boundary has been seen in the trailing N messages,
#     emit a one-screen stderr advisory.
#   - Always exits 0 (advisory only; does not block).
#
# CONFIGURATION (env vars):
#   CC_COMPACT_WATCHDOG_DISABLE        Set to "1" to silence.
#   CC_COMPACT_WATCHDOG_WINDOW         Context window in tokens.
#                                      Default 200000. Set to
#                                      1000000 if you run in 1M mode.
#   CC_COMPACT_WATCHDOG_THRESHOLD      Ratio (0-1) at which to warn
#                                      when no recent compact event
#                                      is seen. Default 0.85.
#   CC_COMPACT_WATCHDOG_LOOKBACK       How many recent transcript
#                                      lines to scan for a
#                                      compact_boundary marker.
#                                      Default 200.
#   CC_COMPACT_WATCHDOG_TRANSCRIPT     Override transcript path
#                                      (used by tests).
#
# UPSTREAM REFERENCES:
#   #63015 (auto-compact never triggers on v2.1.153, 200K Max)
#   #62205 (root-cause analysis of GrowthBook overrides)
#   #17292 (older same-symptom report on v2.1.3; closed not-planned)
# ================================================================

set -u

if [ "${CC_COMPACT_WATCHDOG_DISABLE:-0}" = "1" ]; then
    exit 0
fi

WINDOW="${CC_COMPACT_WATCHDOG_WINDOW:-200000}"
THRESHOLD="${CC_COMPACT_WATCHDOG_THRESHOLD:-0.85}"
LOOKBACK="${CC_COMPACT_WATCHDOG_LOOKBACK:-200}"

INPUT=$(cat 2>/dev/null || true)

TRANSCRIPT_PATH="${CC_COMPACT_WATCHDOG_TRANSCRIPT:-}"
if [ -z "$TRANSCRIPT_PATH" ]; then
    TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Pull the most recent usage block and sum input-side tokens.
LATEST_USAGE=$(grep -h '"usage"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)

if [ -z "$LATEST_USAGE" ]; then
    exit 0
fi

TOTAL=$(printf '%s' "$LATEST_USAGE" | jq -r '
    def num(x): if (x | type) == "number" then x else 0 end;
    (..|objects|select(has("input_tokens"))) as $u
    | (num($u.input_tokens)
       + num($u.cache_read_input_tokens)
       + num($u.cache_creation_input_tokens))
' 2>/dev/null | head -1)

if [ -z "$TOTAL" ] || [ "$TOTAL" = "null" ]; then
    exit 0
fi

# Compute usage ratio. awk handles the float comparison portably.
RATIO=$(awk -v t="$TOTAL" -v w="$WINDOW" 'BEGIN { if (w > 0) printf "%.4f", t / w; else printf "0" }')

OVER=$(awk -v r="$RATIO" -v th="$THRESHOLD" 'BEGIN { print (r + 0 >= th + 0) ? 1 : 0 }')

if [ "$OVER" != "1" ]; then
    exit 0
fi

# Look for compact_boundary marker in the trailing window of the
# transcript. The marker is a substring written by the runtime
# when compaction lands; matching as a substring is conservative.
RECENT_COMPACT=$(tail -n "$LOOKBACK" "$TRANSCRIPT_PATH" 2>/dev/null | grep -c 'compact_boundary' || true)

if [ "${RECENT_COMPACT:-0}" -gt 0 ]; then
    exit 0
fi

# Crossed threshold AND no recent compact event. Emit advisory.
PCT=$(awk -v r="$RATIO" 'BEGIN { printf "%.1f", r * 100 }')

cat >&2 <<EOF

⚠️  Context at ${PCT}% of ${WINDOW} tokens with no compact_boundary
    event in the last ${LOOKBACK} transcript lines.

This is the silent-dispatch failure shape documented in
issue #63015 (Cluster 10 in the cc-safe-setup tracker). The
client's threshold logic and the compaction dispatch are
suspected to be on separate code paths gated by the
\`tengu_compact_cache_prefix\` GrowthBook A/B flag, so the
statusline can report past-threshold while no compaction
fires.

Recovery: run \`/compact\` from the prompt before context
exhaustion. The watchdog can't dispatch compaction on your
behalf — the dispatch path isn't reachable from operator-side.

Silence: set CC_COMPACT_WATCHDOG_DISABLE=1.

EOF

exit 0
